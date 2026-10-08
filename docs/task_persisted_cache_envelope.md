# Aufgaben & Roadmap

## Persistente Cache-Gültigkeit & Metadaten (L2 Storage Envelope)

### Status: Umgesetzt und abgeschlossen

### 1. Problemstellung & Hintergrund
Bisher speicherte Trooper beim Schreiben in den L2-Storage ([`StorageBackend`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_backend.dart)) ausschließlich das vom [`TrooperCodec`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/codec/trooper_codec.dart) serialisierte Datum `T`:
```dart
final serialized = currentCodec.encode(result);
storage.write(key.storageKey, serialized).ignore();
```
Beim Einlesen nach einem App-Neustart (Hydration):
- [`CacheEntry`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_entry.dart) erzeugte standardmäßig `createdAt: DateTime.now()`.
- War die App beispielsweise drei Tage offline oder geschlossen, erhielt der alte Datensatz eine neue TTL ab sofort.
- Veraltete Daten galten fälschlicherweise als frisch (`isFresh == true`), und ein automatisches Revalidieren (SWR: Stale-While-Revalidate) blieb aus.

Darüber hinaus fehlte bei [`StreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart) und [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart) die L2-Persistierung vollständig, obwohl Streams in realen Anwendungen häufig wie persistente Datenquellen (z. B. Firestore, Websocket-Caches) mit Offline-Fähigkeit und Instant-Hydration verwendet werden.

---

### 2. Spezifikation & Lösungsarchitektur

#### A. Envelope-Datenstruktur: [`StorageEnvelope`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_envelope.dart)
Der [`StorageEnvelope`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_envelope.dart) kapselt Nutzdaten und Metadaten:
- `payload`: Der vom Codec erzeugte serialisierte String.
- `createdAt`: Zeitstempel der Erstellung.
- `expiresAt`: Optionaler fixer Ablaufzeitpunkt.
- `timeToLiveMillis`: Optionale TTL in Millisekunden.
- `version`: Versionierung des Envelopes (Standard: 1).
- `isExpired`: Getter, der prüft, ob `expiresAt` in der Vergangenheit liegt.
- `encode()` / `decode()` / `tryDecode()`: JSON-Serialisierung und fehlertolerantes Parsen.

#### B. Kein Legacy-Fallback
Da das System vor dem Produktiveinsatz steht, existiert kein abwärtskompatibler Fallback für raw JSON ohne Envelope. Beschädigte oder unbekannte Formate werden im L2 Storage gelöscht (`storage.delete`).

#### C. Policy-Gekoppelte Instant-Hydration
- **Frische L2-Daten** (`!envelope.isExpired`): Werden sofort als `DataLoaded` emittiert und in L1 (`CacheStore`) abgelegt (Cache-Hit).
- **Abgelaufene L2-Daten** (`envelope.isExpired`):
  - Bei `stalePolicy == StalePolicy.keepStaleWhileRevalidate`: Werden sofort als `DataRefreshing` emittiert (SWR), während im Hintergrund automatisch die Revalidierung bzw. der Upstream-Verbindungsaufbau läuft.
  - Bei `stalePolicy == StalePolicy.discardStaleOnRefresh`: Werden verworfen, aus L2 gelöscht und ein regulärer Ladezustand (`DataLoading`) wird emittiert.

---

### 3. Umgesetzte Komponenten

- [x] [`StorageEnvelope`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_envelope.dart)
  - Erstellt mit Payload, Metadaten, Ablauflogik und JSON-Serialisierung.
  - Exportiert in [`trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/trooper.dart).
- [x] [`CacheEntry`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_entry.dart)
  - `expiresAt` im Konstruktor und in `copyWith()` integriert, um historische Ablaufzeitpunkte exakt wiederherzustellen.
- [x] [`TrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_query.dart)
  - Speichert `StorageEnvelope` beim Fetch und via `set()`.
  - Liest `StorageEnvelope` bei `get()` und unterscheidet frische vs. abgelaufene Daten gemäß `StalePolicy`.
- [x] [`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart)
  - Speichert `StorageEnvelope` beim Fetch und via `setKey()`.
  - Liest `StorageEnvelope` bei `getKey()` mit SWR-Revalidierung.
- [x] [`LocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart)
  - Speichert `StorageEnvelope` via `set()`.
  - Hydratisiert via `get()` mit Prüfung auf Ablaufzeitpunkt.
- [x] [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart)
  - Speichert `StorageEnvelope` via `setKey()`.
  - Hydratisiert via `getKey()` mit Prüfung auf Ablaufzeitpunkt.
- [x] [`StreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart)
  - `codec: TrooperCodec<T>?` im Konstruktor und in `fromStream()` ergänzt.
  - Speichert empfangene Upstream-Events und `set()` in L2 mit `StorageEnvelope`.
  - Instant-Hydration in `connect()` und L2-Check in `get()` unter Berücksichtigung der `StalePolicy`.
- [x] [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart)
  - `codec: TrooperCodec<T>?` im Konstruktor und in `fromStream()` ergänzt.
  - Speichert empfangene Upstream-Events und `setKey()` in L2 mit `StorageEnvelope`.
  - Instant-Hydration in `connectKey()` und L2-Check in `getKey()` unter Berücksichtigung der `StalePolicy`.
