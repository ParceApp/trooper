# Aufgaben & Roadmap

## 1. Überprüfung der strikten Parameter-Handhabung

### Status: Umgesetzt und abgeschlossen

### Problemstellung & Hintergrund
Bisher gab es an einigen Stellen "smartes" bzw. implizites Fallback-Verhalten für Parameter `P`:
- Wenn kein Parameter übergeben wurde oder `_lastParams` leer war, wurde versucht, zur Laufzeit zu erraten, ob `()` oder der letzte Parameter (`lastParam`) eingesetzt werden kann (z. B. `_lastParams.remove(key) ?? (const () is P ? const () as P : null)`).
- Dies führte zu Intransparenz darüber, mit welchen Parametern Cache-, Storage- oder Lifecycle-Operationen tatsächlich ausgeführt werden.

### Neuer Plan & Vorgabe
1. **Kein "smartes" Parameter-Raten mehr**: Parameter werden nicht mehr implizit im Hintergrund durch magische Fallbacks wie `()` oder `lastParam` ersetzt.
2. **Explizite Übergabe**:
   - Wenn ein Parameter für eine Operation benötigt wird, muss er explizit übergeben werden.
   - Wenn ein Trooper parameterlos ist (`P == ()`), erfolgt der bequeme Zugriff ausschließlich über typisierte Extensions (z. B. [`ParameterlessAccessor`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/accessor.dart#L60), [`ParameterlessTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper.dart)), nicht über Laufzeit-Typ-Weichen mitten in der Core-Logik.
3. **Klarheit bei Lifecycle & Invalidation**:
   - Für Methoden ohne Parameter (z. B. `invalidate()`, `invalidateKey(key)`, `removeKey(key)`): Gezielte Parameter-Invalidierung kann explizit übergeben werden (`invalidateKey(key, [parameter])`), andernfalls wird mit Wildcards (`removeWhere`) im Cache/Storage sauber gearbeitet, ohne unvollständige QueryKeys zu erraten.

### Zu überprüfende Komponenten & Dateien

- [x] [`TrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_query.dart)
  - `get`, `watch`, `refresh`, `trigger`
  - Revalidation & Dependency-Handling
- [x] [`KeyedTrooperQuery`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_trooper_query.dart)
  - `getKey`, `watchKey`, `refreshKey`, `triggerKey`, `setKey`, `getMany`
  - `_lastParams`-Nutzung in `invalidateKey`, `invalidate`, `removeKey`, `recover`, `didChangeDependencies`
- [x] [`LocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/local_trooper.dart)
  - `set`, `update`, `reset`, `get`, `watch`
  - `initialize` und `didChangeDependencies`
- [x] [`KeyedLocalTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_local_trooper.dart)
  - `getKey`, `setKey`, `updateKey`, `resetKey`, `refreshKey`, `triggerKey`, `watchKey`
  - `_lastParams`-Nutzung und Fallbacks in `removeKey`, `invalidateKey`, `invalidate`
- [x] [`StreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/stream_trooper.dart)
  - `connect`, `watch`, `get`, `refresh`
  - Auto-Reconnect in `resume`, `recover`, `didChangeDependencies`
- [x] [`KeyedStreamTrooper`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_stream_trooper.dart)
  - `connectKey`, `watchKey`, `getKey`, `refreshKey`, `triggerKey`, `setKey`
  - Auto-Reconnect und Fallbacks in `resume`, `recover`, `didChangeDependencies`, `invalidateKey`
- [x] [`TrooperMutation`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/trooper_mutation.dart)
  - `call`, `execute`
- [x] [`Accessor`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/accessor.dart) & [`KeyedAccessor`](file:///Users/hannes/Developer/trooper/packages/trooper/lib/src/core/keyed_accessor.dart)
  - Signaturen für `Map<K, T>` vs. Einzel-Key-Zugriffe
