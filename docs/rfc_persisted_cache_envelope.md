# RFC: Persistente Cache-Gültigkeit & Metadaten (L2 Storage Envelope)

## 1. Problemstellung

Aktuell speichert Trooper beim Schreiben in den L2-Storage ([`StorageBackend`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_backend.dart)) ausschließlich das vom [`TrooperCodec`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/codec/trooper_codec.dart) serialisierte Datum `T`:

```dart
// Aktuell in TrooperQuery / KeyedTrooperQuery / LocalTrooper:
final serialized = currentCodec.encode(result);
storage.write(key.storageKey, serialized).ignore();
```

Beim Wiederherstellen nach einem App-Neustart (Hydration):
```dart
final restoredData = currentCodec.decode(serialized);
cache.put(
  key,
  restoredData,
  timeToLive: config.timeToLive,
  source: DataSource.storage,
);
```

### Die Konsequenz
- [`CacheEntry`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_entry.dart) erzeugt beim Aufruf von `cache.put` standardmäßig `createdAt: DateTime.now()`.
- War die App z. B. 3 Tage offline oder geschlossen, wird der 3 Tage alte Datensatz aus dem Speicher geladen und erhält eine **neue TTL ab jetzt** (z. B. `DateTime.now().add(10 Minuten)`).
- **Fehlverhalten:** Veraltete Daten gelten fälschlicherweise für die volle TTL als frisch (`isFresh == true`). Ein automatisches Revalidieren (SWR / Stale-While-Revalidate) findet nicht statt, weil das System den Datensatz für aktuell hält.

---

## 2. Ziel

- Speichern von Erstellungszeitpunkt (`createdAt`), Ablaufzeitpunkt (`expiresAt`) und optional TTL (`timeToLiveMillis`) zusammen mit den Nutzdaten im Storage.
- Beim Laden aus L2 Storage wird der [`CacheEntry`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_entry.dart) mit den echten historischen Zeitstempeln restauriert.
- Ist der Eintrag abgelaufen (`isExpired == true`), wird er korrekt als stale erkannt und triggert sofort die Hintergrund-Revalidierung (SWR).
- Volle Abwärtskompatibilität: Rohdaten ohne Envelope (z. B. aus vorherigen Versionen oder Plain-JSON-Dateien) können als Fallback weiterhin eingelesen werden.

---

## 3. Lösungsentwurf: `StorageEnvelope`

### A. Envelope-Datenstruktur
Ein leichtgewichtiger Umschlag im Storage, der Metadaten und die Nutzdaten trennt:

```dart
class StorageEnvelope {
  const StorageEnvelope({
    required this.payload,
    required this.createdAt,
    this.expiresAt,
    this.timeToLiveMillis,
  });

  final String payload;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int? timeToLiveMillis;

  Map<String, dynamic> toJson() => {
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (timeToLiveMillis != null) 'timeToLiveMillis': timeToLiveMillis,
  };

  static StorageEnvelope? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic> &&
          json.containsKey('payload') &&
          json.containsKey('createdAt')) {
        return StorageEnvelope(
          payload: json['payload'] as String,
          createdAt: DateTime.parse(json['createdAt'] as String),
          expiresAt: json['expiresAt'] != null
              ? DateTime.parse(json['expiresAt'] as String)
              : null,
          timeToLiveMillis: json['timeToLiveMillis'] as int?,
        );
      }
    } catch (_) {
      // Ignorieren falls Legacy-Format
    }
    return null;
  }
}
```

---

## 4. Benötigte Änderungen im Code

### 1. `CacheEntry<T>` erweitern
In [`cache_entry.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_entry.dart):
- Konstruktor-Unterstützung für explizites `expiresAt` (bereits vorhanden via `createdAt` und `timeToLive`, kann aber noch robuster gemacht werden, falls `expiresAt` direkt übergeben wird).

### 2. `MemoryCache.putEntry(CacheKey key, CacheEntry entry)`
Erlaubt das direkte Ablegen eines bereits initialisierten `CacheEntry` in den L1-Cache, ohne dass `createdAt` mit `DateTime.now()` überschrieben wird.

### 3. Schreiben in L2 Storage (`TrooperQuery`, `KeyedTrooperQuery`, `LocalTrooper`)
```dart
final serializedPayload = currentCodec.encode(result);
final envelope = StorageEnvelope(
  payload: serializedPayload,
  createdAt: entry.createdAt,
  expiresAt: entry.expiresAt,
  timeToLiveMillis: config.timeToLive?.inMilliseconds,
);

final serializedEnvelope = jsonEncode(envelope.toJson());
storage.write(key.storageKey, serializedEnvelope).ignore();
```

### 4. Lesen aus L2 Storage (Hydration)
```dart
final rawStorageData = await storage.read(key.storageKey);
if (rawStorageData != null) {
  try {
    final envelope = StorageEnvelope.tryParse(rawStorageData);
    final String payload;
    final DateTime createdAt;
    final Duration? ttl;

    if (envelope != null) {
      payload = envelope.payload;
      createdAt = envelope.createdAt;
      ttl = envelope.timeToLiveMillis != null
          ? Duration(milliseconds: envelope.timeToLiveMillis!)
          : config.timeToLive;
    } else {
      // Abwärtskompatibler Fallback für Legacy-Daten ohne Envelope
      payload = rawStorageData;
      createdAt = DateTime.now();
      ttl = config.timeToLive;
    }

    final restoredData = currentCodec.decode(payload);
    final restoredEntry = CacheEntry<T>(
      restoredData,
      createdAt: createdAt,
      timeToLive: ttl,
      source: DataSource.storage,
    );

    cache.putEntry(key, restoredEntry);

    // Wenn frisch -> Hit
    // Wenn stale -> Hit als stale emittieren, Daten ausgeben und Revalidation im Hintergrund anstoßen
    ...
  } catch (_) {
    storage.delete(key.storageKey).ignore();
  }
}
```

---

## 5. Vorteile
1. **Präzises SWR nach App-Neustart:** Veraltete Cache-Daten auf Disk werden sofort als stale markiert. Die UI zeigt sie zwar direkt an (kein Lade-Spinner), aber der Trooper startet unverzüglich einen Netzwerk-Refetch.
2. **Offline-Fähigkeit:** Auch offline ist sofort ersichtlich, wie alt die Daten sind (`age` bzw. `DataMetadata.fetchedAt`).
3. **Migration:** Durch den Fallback entstehen keine Breaking Changes für bestehende lokale Datenbanken oder Caches.
