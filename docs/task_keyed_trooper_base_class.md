# Aufgabe & Spezifikation: Basisklasse KeyedTrooper

### Status: Umgesetzt und abgeschlossen

---

## 1. Motivation & Zielsetzung

In Trooper existiert für Single-Ressourcen bereits eine saubere abstrakte Basisklasse [`Trooper<T, P>`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper.dart#L26), von der alle konkreten Single-Varianten erben:
- [`TrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_query.dart)
- [`LocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart)
- [`StreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart)

Für die Keyed-Sammlungen ([`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart), [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart), [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart)) fehlt dieses Gegenstück bisher. Alle drei Klassen implementieren unabhängig voneinander Interfaces wie [`LifecycleAware`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/lifecycle/lifecycle_aware.dart), [`Invalidatable`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/invalidatable.dart) und [`KeyedAccessor`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_accessor.dart).

### Die Konsequenzen des aktuellen Status quo:
1. **Über 500 Zeilen Code-Duplizierung**:
   Die gesamte Fassade für [`KeyedAccessor`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_accessor.dart) (`operator []`, `key()`, `watchAll()`, `watchKeys()`, `currentStates`, `currentDataMap`, `activeKeys`, `count`), die [`Accessor<Map<K, T>, ()>`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/accessor.dart)-Methoden (`get`, `watch`, `refresh`, `trigger`, `current`, `currentData`), das Parameter-Tracking (`_lastParams`) und der Ressourcen-Cleanup in `dispose()` sind dreimal nahezu identisch kopiert.
2. **Inkonsistenzen im Detail**:
   Hilfsmethoden wie `runSideEffect` sind in [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart#L231) `@protected`, in [`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart#L491) und [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart#L194) aber `private`.
3. **Fehlende Polymorphie**:
   Konsumenten oder Controller können nicht generisch einen `KeyedTrooper<K, T, P>` entgegennehmen, sondern müssen entweder den konkreten Implementierungstyp oder das reine Read-Only-Interface `KeyedAccessor` nutzen.

### Das Ziel:
Einführung einer abstrakten Basisklasse [`KeyedTrooper<K extends Object, T, P extends Parameter>`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper.dart) als spiegelbildliches Äquivalent zu `Trooper<T, P>`.

---

## 2. Architektur & Klassendesign

### A. Klassenhierarchie

```text
                  LifecycleAware
                        │
       ┌────────────────┴────────────────┐
       │                                 │
   Trooper<T, P>               KeyedTrooper<K, T, P>
       │                                 │
       ├─ TrooperQuery                   ├─ KeyedTrooperQuery
       ├─ LocalTrooper                   ├─ KeyedLocalTrooper
       └─ StreamTrooper                  └─ KeyedStreamTrooper
```

### B. Spezifikation der Basisklasse `KeyedTrooper`

```dart
// lib/src/core/keyed_trooper.dart
import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/types/parameter.dart';

/// Abstrakte Basisklasse für alle Keyed-Trooper-Sammlungen.
abstract class KeyedTrooper<K extends Object, T, P extends Parameter>
    with LifecycleAware
    implements Invalidatable, KeyedAccessor<K, T, P> {
  KeyedTrooper({
    required this.namespace,
    this.sideEffects,
    TrooperConfig? config,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) : config = config ?? defaultConfig,
       _ownsCache = (cache == null),
       _ownsQueryQueue = (queryQueue == null),
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       stream = stream ?? KeyedStatefulStream<K, T>();

  static TrooperConfig get defaultConfig => TrooperConfig.defaultConfig;

  final bool _ownsCache;
  final bool _ownsQueryQueue;

  /// Logischer Namespace der Keyed-Query-Familie.
  final String namespace;

  /// Konfiguration für Caching, Staleness und Persistence.
  final TrooperConfig config;

  /// Optionale Side-Effect-Callbacks.
  final KeyedTrooperSideEffects<K, T, P>? sideEffects;

  /// L1-Memory-Cache.
  final CacheStore cache;

  /// Concurrency- und Request-Queue.
  final TrooperQueryQueue queryQueue;

  /// Telemetrie-Hub für Events.
  final TelemetryHub telemetry;

  /// Reaktiver Keyed-Stream für alle Keys.
  final KeyedStatefulStream<K, T> stream;

  final Map<K, P> _lastParams = {};
  bool _isDisposed = false;

  /// Gibt an, ob dieser Trooper freigegeben wurde.
  bool get isDisposed => _isDisposed;

  /// Gibt den zuletzt für [key] verwendeten Parameter zurück.
  P? lastParamOf(K key) => _lastParams[key];

  /// Speichert den zuletzt verwendeten Parameter für [key].
  @protected
  void recordParam(K key, P parameter) {
    _lastParams[key] = parameter;
  }

  /// Erstellt den eindeutigen QueryKey für [key] und [parameter].
  @protected
  QueryKey buildQueryKey(K key, P parameter) {
    recordParam(key, parameter);
    return QueryKey.keyed(namespace, key: key, parameter: parameter);
  }

  /// Prüft, ob sich der Parameter für [key] gegenüber dem letzten Aufruf geändert hat.
  @protected
  bool isParamChanged(K key, P parameter) {
    final last = _lastParams[key];
    if (last == null) return false;
    return parameter != last;
  }

  /// Führt einen Side-Effect-Callback sicher und geschützt aus.
  @protected
  void runSideEffect(FutureOr<void> Function()? callback) {
    if (callback == null) return;
    try {
      final result = callback();
      if (result is Future) {
        result.ignore();
      }
    } catch (_) {
      // Non-critical side-effect failure
    }
  }

  // --- KeyedAccessor Fassade (einmalig für alle Keyed-Trooper) ---

  late final KeyedAccessor<K, T, P> accessor = KeyedTrooperAccessor<K, T, P>(
    accessorFactory: (k) => this[k],
    stream: stream,
    onInvalidate: invalidate,
    onInvalidateKey: invalidateKey,
    onRefresh: () async {
      invalidate();
      return currentDataMap;
    },
  );

  @override
  Accessor<T, P> operator [](K key);

  @override
  Accessor<T, P> key(K key) => this[key];

  @override
  Map<K, StatefulData<T>> get currentStates => stream.currentStates;

  @override
  Map<K, T> get currentDataMap => stream.currentDataMap;

  @override
  Set<K> get activeKeys => stream.activeKeys;

  @override
  int get count => stream.count;

  @override
  Stream<Map<K, StatefulData<T>>> watchAll() => stream.watchAll();

  @override
  Stream<Set<K>> watchKeys() => stream.watchKeys();

  // --- Accessor<Map<K, T>, ()> Methoden für Collection-Ebene ---

  @override
  StatefulStream<Map<K, T>> watch(() parameter, {bool eager = true}) =>
      accessor.watch(parameter, eager: eager);

  @override
  Future<Map<K, T>> get(() parameter, {bool forceRefresh = false}) =>
      accessor.get(parameter, forceRefresh: forceRefresh);

  @override
  Future<Map<K, T>> refresh(() parameter) => accessor.refresh(parameter);

  @override
  void trigger(() parameter, {bool forceRefresh = false}) =>
      accessor.trigger(parameter, forceRefresh: forceRefresh);

  @override
  StatefulData<Map<K, T>> current(() parameter) => accessor.current(parameter);

  @override
  Map<K, T>? currentData(() parameter) => accessor.currentData(parameter);

  // --- Synchrone Key-Zustände ---

  StatefulData<T> currentKey(K key) => stream.stateOf(key);
  T? currentKeyData(K key) => stream.dataOf(key);

  // --- Lifecycle & Ressourcen-Freigabe ---

  Future<void> clearAll() async {
    _lastParams.clear();
    cache.removeName(namespace);
    await stream.clearAll();
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _lastParams.clear();
    await stream.dispose();
    if (_ownsQueryQueue) {
      await queryQueue.dispose();
    }
    if (_ownsCache) {
      await cache.dispose();
    }
  }
}
```

---

## 3. Was sich in den Subklassen vereinfacht

Durch die Basisklasse schrumpfen die Subklassen drastisch, da sie sich nur noch auf ihre jeweilige Kernkompetenz konzentrieren:

### A. [`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart)
- **Fällt weg**: Deklaration von `namespace`, `config`, `cache`, `queryQueue`, `telemetry`, `stream`, `_ownsCache`, `_ownsQueryQueue`, `_lastParams`, `buildQueryKey`, `_runSideEffect`, alle 10 Collection-Accessor-Methoden und der Großteil von `dispose()`.
- **Bleibt**: Die eigentliche Datenabfrage `fetch`, `getKey`, `watchKey`, `refreshKey`, `triggerKey`, `setKey`, `getMany`, `_executeFetch` und der gebundene `_KeyedBoundAccessor`.

### B. [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart)
- **Fällt weg**: Gleiche Boilerplate-Felder und Accessor-Implementierung, `_runSideEffect` und Parameter-Tracking.
- **Bleibt**: `initialValueFactory`, Hydration-Logik aus L2-Storage, `getKey`, `setKey`, `updateKey`, `resetKey`, `watchKey` und `_KeyedLocalBoundAccessor`.

### C. [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart)
- **Fällt weg**: Gleiche Boilerplate-Felder, `runSideEffect`, `_currentParams` (wird durch geerbtes `_lastParams` ersetzt), alle Accessor-Methoden.
- **Bleibt**: Upstream-Stream-Subscription pro Key (`connectKey`, `disconnectKey`), Listener-Zählung (`_activeWatchers`), Reconnect-Logik bei `resume()` und `_KeyedStreamBoundAccessor`.

---

## 4. Umsetzungs- und Migrationsplan

### Schritt 1: Neue Basisklasse anlegen
- Datei `packages/trooper/lib/src/core/keyed_trooper.dart` erstellen.
- Konstruktor und gemeinsame Member wie oben spezifiziert implementieren.
- In [`packages/trooper/lib/trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/trooper.dart) exportieren.

### Schritt 2: `KeyedTrooperQuery` umstellen
- `class KeyedTrooperQuery<K extends Object, T, P extends Parameter> extends KeyedTrooper<K, T, P>`
- `super(...)`-Aufruf im Konstruktor nutzen.
- Redundante Felder, `_runSideEffect` und duplizierte Accessor-Methoden entfernen.

### Schritt 3: `KeyedLocalTrooper` umstellen
- `class KeyedLocalTrooper<K extends Object, T, P extends Parameter> extends KeyedTrooper<K, T, P>`
- `super(...)`-Aufruf im Konstruktor nutzen.
- Redundante Felder und Methoden entfernen.

### Schritt 4: `KeyedStreamTrooper` umstellen
- `class KeyedStreamTrooper<K extends Object, T, P extends Parameter> extends KeyedTrooper<K, T, P>`
- `super(...)`-Aufruf im Konstruktor nutzen.
- Redundante Felder und Methoden entfernen.

### Schritt 5: Verifikation
- `dart analyze` ausführen: Sicherstellen, dass 0 Fehler, 0 Warnungen und 0 Lints existieren.
- Verifizieren, dass die Public API von [`KeyedAccessor`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_accessor.dart) unverändert bleibt.

---

## 5. Betroffene Dateien

- Neu: `packages/trooper/lib/src/core/keyed_trooper.dart`
- [`packages/trooper/lib/src/core/keyed_trooper_query.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart)
- [`packages/trooper/lib/src/core/keyed_local_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart)
- [`packages/trooper/lib/src/core/keyed_stream_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart)
- [`packages/trooper/lib/trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/trooper.dart)
