# Aufgabe: Vollständiger Dokumentations- und Kommentar-Audit über alle Dateien

### Status: Offen

---

## 1. Zielsetzung & Problemstellung
Im Zuge der Weiterentwicklung des Packages wurden wesentliche Methoden und Klassen verfeinert und vereinheitlicht (z. B. `.get(...)` statt `.read(...)`, `namespace:` statt `name:`, `TrooperQueryQueue` statt `RequestOrchestrator`, `StorageEnvelope`, `KeyedTrooper`).

Aktuell weisen jedoch einige Doc-Comments in `lib/` sowie das Haupt-[`README.md`](file:///Users/hannes/Developer/trooper/packages/trooper/README.md) und [`CHANGELOG.md`](file:///Users/hannes/Developer/trooper/packages/trooper/CHANGELOG.md) veraltete Signaturen, ungenaue Beschreibungen oder nicht existierende Konstruktor-Referenzen auf.

Ziel dieser Aufgabe ist eine lückenlose, dateiübergreifende Prüfung **jeder einzelnen Datei**, **jedes Doc-Comments** und **aller Markdown-Dokumentationen** auf exakte Übereinstimmung mit dem aktuellen Code.

---

## 2. Detaillierter Audit-Katalog

### A. Hauptdokumentation ([`packages/trooper/README.md`](file:///Users/hannes/Developer/trooper/packages/trooper/README.md))
- [ ] **Methoden-Aufrufe**: Alle Vorkommen von `.read(parameter: ...)` durch `.get(...)` ersetzen.
- [ ] **Keyed Accessor Aufrufe**: `orders[42].read()` durch `orders[42].get()` ersetzen.
- [ ] **Parameter-Namen im Controller**: `name: 'user_profile'` durch `namespace: 'user_profile'` korrigieren.
- [ ] **Mutation-Aufrufe**: `controller.updateBio(parameter: ...)` zu `controller.updateBio(...)` (positionales Record) korrigieren.
- [ ] **Config-Konstruktoren**: Nicht existente Konstruktoren wie `TrooperConfig.longCached()` und `TrooperConfig.ephemeral()` durch `TrooperConfig(timeToLive: Duration(hours: 1))` bzw. `TrooperConfig.noCache()` ersetzen.
- [ ] **Klassennamen**: Veraltete Erwähnungen von `RequestOrchestrator` durch `TrooperQueryQueue` ersetzen.
- [ ] **Codebeispiele validieren**: Sicherstellen, dass jeder Codeblock im README 1:1 fehlerfrei kompilierbar ist.

### B. Changelog ([`packages/trooper/CHANGELOG.md`](file:///Users/hannes/Developer/trooper/packages/trooper/CHANGELOG.md))
- [ ] `readMany` zu `getMany` korrigieren.
- [ ] `RequestOrchestrator` zu `TrooperQueryQueue` anpassen.
- [ ] Ergänzung der neuen Features: `StorageEnvelope` L2-Persistenz, `KeyedTrooper`-Basisklasse, `TrooperController`-Export.

### C. Dateiprüfung in `lib/src/` (Kommentare & API-Docs)

#### 1. Core & Accessors
- [ ] [`lib/src/core/accessor.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/accessor.dart): Alle Doc-Comments für `get`, `watch`, `refresh`, `trigger`, `current`, `currentData`, `invalidate` und `ParameterlessAccessor` prüfen.
- [ ] [`lib/src/core/keyed_accessor.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_accessor.dart): Prüfung von `operator []`, `key()`, `watchAll()`, `watchKeys()`, `currentStates`, `currentDataMap`, `activeKeys`, `count`.
- [ ] [`lib/src/core/trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper.dart): Abstrakte Basisklasse, Lifecycle und Parameterless-Extensions prüfen.
- [ ] [`lib/src/core/keyed_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper.dart): Vollständige Doc-Comments der neuen Basisklasse verifizieren.
- [ ] [`lib/src/core/trooper_query.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_query.dart): SWR, L1/L2 StorageEnvelope, QueryQueue und Revalidation-Docs prüfen.
- [ ] [`lib/src/core/keyed_trooper_query.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart): Keyed-Queries, Batch-Lesen (`getMany`), SWR und L2-Persistenz prüfen.
- [ ] [`lib/src/core/local_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart): In-Memory-Verhalten, L2 StorageEnvelope, `set`, `update`, `reset` prüfen.
- [ ] [`lib/src/core/keyed_local_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart): Keyed In-Memory-Verhalten und L2-Persistenz prüfen.
- [ ] [`lib/src/core/stream_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart): Push-Stream, Reconnect-Lifecycle, `codec`-Parameter und L2-Persistenz prüfen.
- [ ] [`lib/src/core/keyed_stream_trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart): Keyed Push-Streams, Multi-Channel-Lifecycle, `codec` und L2-Persistenz prüfen.
- [ ] [`lib/src/core/trooper_mutation.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_mutation.dart): FIFO-Queue, Invalidation-Kaskade, `call` und `execute` Signaturen prüfen.

#### 2. Controller
- [ ] [`lib/src/controller/trooper_controller.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/controller/trooper_controller.dart):
  - Referenzen auf `[defaultOrchestrator]` zu `[defaultQueryQueue]` korrigieren.
  - Parameter `namespace:` in allen Factory-Methoden-Dokumentationen (`query`, `keyedQuery`, `local`, `keyedLocal`, `stream`, `keyedStream`, `mutation`) verifizieren.
  - Lifecycle-Hooks (`onInit`, `onPause`, `onResume`, `onRecover`, `onDependenciesChanged`, `onDispose`) und Extra-Getter (`extraInvalidatables`, `extraLifecycleChildren`) prüfen.

#### 3. Configuration & Concurrency
- [ ] [`lib/src/config/query_conflict_policy.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/config/query_conflict_policy.dart):
  - Alle Code-Beispiele mit `query.read(parameter: ...)` durch `query.get(...)` ersetzen.
  - Dokumentation von `cancel`, `forward` und `parallel` prüfen.
- [ ] [`lib/src/config/trooper_config.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/config/trooper_config.dart):
  - `hasCache`, `noCache()`, StalePolicy, ConflictPolicy und Storage dokumentieren.
- [ ] [`lib/src/config/stale_policy.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/config/stale_policy.dart): Dokumentation von `keepStaleWhileRevalidate` und `discardStaleOnRefresh`.
- [ ] [`lib/src/concurrency/query_queue.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/concurrency/query_queue.dart): Coalescing, Dedup und Conflict Resolution dokumentieren.
- [ ] [`lib/src/concurrency/mutation_queue.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/concurrency/mutation_queue.dart): Sequentielle FIFO-Queue dokumentieren.
- [ ] [`lib/src/concurrency/cancel_token.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/concurrency/cancel_token.dart): Kooperative Cancellation dokumentieren.

#### 4. Storage, Cache & Codec
- [ ] [`lib/src/storage/storage_envelope.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_envelope.dart): Metadaten, Zeitstempel, Ablauflogik und JSON-Parsing dokumentieren.
- [ ] [`lib/src/storage/cache_entry.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_entry.dart): `createdAt`, `expiresAt`, `timeToLive` und Metadaten-Mapping dokumentieren.
- [ ] [`lib/src/storage/cache_store.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/cache_store.dart): L1 Memory-Cache, Sweep-Eviction und Invalidation dokumentieren.
- [ ] [`lib/src/storage/storage_backend.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/storage_backend.dart): L2 Storage-Interface dokumentieren.
- [ ] [`lib/src/storage/invalidatable.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/storage/invalidatable.dart): Invalidation-Interface dokumentieren.
- [ ] [`lib/src/codec/trooper_codec.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/codec/trooper_codec.dart): Serialisierung und Standard-Codecs (`string`, `json`, `int`, etc.) prüfen.

#### 5. State, Streams & Telemetry
- [ ] [`lib/src/state/stateful_data.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/state/stateful_data.dart): Sealed State-Hierarchie (`DataInitial`, `DataLoading`, `DataLoaded`, `DataRefreshing`, `DataError`) dokumentieren.
- [ ] [`lib/src/state/data_metadata.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/state/data_metadata.dart): `DataMetadata`, `DataSource`, `fetchedAt`, `expiresAt` dokumentieren.
- [ ] [`lib/src/stream/stateful_stream.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/stream/stateful_stream.dart) & [`stateful_stream_controller.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/stream/stateful_stream_controller.dart): Stream-Filter, Sync-Emission und Lifecycle prüfen.
- [ ] [`lib/src/stream/keyed_stateful_stream.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/stream/keyed_stateful_stream.dart): Multi-Key-Stream-Orchestrierung dokumentieren.
- [ ] [`lib/src/telemetry/telemetry_hub.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/telemetry/telemetry_hub.dart), [`trooper_event.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/telemetry/trooper_event.dart), [`trooper_logger.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/telemetry/trooper_logger.dart): Telemetrie-Pipeline und Logging dokumentieren.
- [ ] [`lib/src/effects/`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/effects/): Side-Effects für Standard, Keyed und Mutations prüfen.
- [ ] [`lib/src/error/trooper_exception.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/error/trooper_exception.dart): Exception-Hierarchie prüfen.
- [ ] [`lib/types/parameter.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/types/parameter.dart): `Parameter = Record` Typedef dokumentieren.

---

## 3. Akzeptanzkriterien
1. **Keine veralteten Signaturen**: Kein einziges Vorkommen von `.read(parameter: ...)` oder `name:` in Code-Beispielen oder Doc-Comments.
2. **Kompilierbare Code-Snippets**: Alle Code-Beispiele in `README.md` und Doc-Comments sind syntaktisch und semantisch gültiger Dart 3-Code.
3. **Vollständige Export-Dokumentation**: In [`lib/trooper.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/trooper.dart) sind alle öffentlichen Symbole beschrieben.
4. **Dart Doc Validierung**: `dart doc` baut ohne Warnungen und generiert vollständige API-Referenzen.
