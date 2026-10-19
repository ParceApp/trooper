# Entscheidungsvorlage: API-Freeze für 1.0

Grundlage: `docs/audit/findings.md` (freeze-relevante Findings), `docs/audit/api-inventory.md`, Stand
`ai/affectionate-perlman-8eb1d4` (P0- und P1-Korrektheitsfixes enthalten). Jede Entscheidung unten ist nach 1.0 nur
per Major-Release umkehrbar. **Empfehlung** ist jeweils fett markiert; Abweichungen von der Audit-Empfehlung sind
begründet.

**Status (2026-10-19): vom Nutzer bestätigt, alle Empfehlungen werden so umgesetzt.**

Eine Dart-Regel bestimmt mehrere Punkte: Ist eine Klasse `base`, muss **jede** Unterklasse ebenfalls `base`, `final`
oder `sealed` sein, auch beim Nutzer. `abstract base class TrooperController` hieße also: Jeder Nutzer muss
`final class CourseController extends TrooperController` schreiben, sonst kompiliert sein Code nicht.

---

## F-044 · Parameterless-Extensions (51 verdeckte Member)

Instanzmethoden verdecken alle gleichnamigen Extension-Member; `q.get()` kompiliert nicht.

| Option | Aufruf für `P = ()` | Typsicherheit | Oberfläche |
|---|---|---|---|
| **A: Extensions entfernen, `()` explizit übergeben** | `q.get(())`, `kq.getKey(1, ())`, `m(())`, `q.watch(initialParameter: ())` | Fehlender Parameter ist Compile-Fehler | −9 Extensions, −51 Member |
| B: Parameter optional machen (`[P? parameter]`), zur Laufzeit `()` einsetzen | `q.get()` | `userQuery.get()` mit `P = (int,)` kompiliert und wirft erst zur Laufzeit `ArgumentError` | Signaturen aller Kernmethoden ändern sich |
| C: Extension-Member umbenennen (z. B. `getUnit()`) | `q.getUnit()` | sicher | zweiter Name je Methode, 51 Member eingefroren |

**Empfehlung A.** `()` ist der idiomatische Dart-3-Wert für „kein Parameter“. B tauscht einen Compile-Fehler gegen
einen Laufzeitfehler in der meistgenutzten API. Eine Kurzform lässt sich nach 1.0 additiv nachrüsten, falls Nutzer
sie vermissen; das Entfernen nicht.

## F-029 · 38 Klassen ohne Modifier

| Gruppe | Klassen | Audit-Vorschlag | **Empfehlung** |
|---|---|---|---|
| Konkrete Troopers, Konfiguration, Infrastruktur | `QueryTrooper`, `KeyedQueryTrooper`, `LocalTrooper`, `KeyedLocalTrooper`, `StreamTrooper`, `KeyedStreamTrooper`, `TrooperMutation`, `LoadMore`, `TrooperConfig`, `RetryPolicy`, `TrooperSideEffects`, `KeyedTrooperSideEffects`, `TrooperMutationSideEffects`, `CacheStore`, `CacheEntry`, `DataMetadata`, `TelemetryHub`, `StatefulStream`, `TrooperCancelToken`, `TrooperQueryQueue`, `TrooperMutationQueue`, `InMemoryStorageBackend`, `StorageEnvelope`, `ConsoleTrooperLogger`, `FakeAccessor` | `final` | **`final`** |
| Interne Basisklassen | `Trooper`, `KeyedTrooper` | `abstract base` | **`abstract base`**; Infrastruktur-Member (`streamController`, `stream`, `cache`, `queryQueue`, `recordParam`, `buildQueryKey` …) werden `@internal`. Eigene Trooper-Unterklassen sind kein unterstützter Erweiterungspunkt. |
| `TrooperCodec` | | `abstract base` | **`abstract final`**: Der Konstruktor ist schon privat, Nutzer bauen Codecs über `TrooperCodec.custom/json/list/map`. `final` schließt zusätzlich `implements` aus. |
| Vom Nutzer zu erweiternde Basisklassen | `TrooperController`, `Tloc`, `Tubit`, `TlocEvent` | `abstract base` | **ohne Modifier lassen**, Policy dokumentieren: „Nur `extends`; `implements` wird nicht unterstützt, neue Member können in Minor-Releases hinzukommen“ (so halten es Flutter und `bloc`). `base` würde jede Nutzer-Unterklasse brechen (siehe Vorbemerkung). Alternative: `abstract base` und `final class X extends …` in allen Beispielen. |
| Widget | `TlocEffectListener` | offen | **offen** (Flutter-Konvention) |
| Interna | `KeyedTrooperAccessor`, `KeyedStatefulStream`, `StatefulStreamController`, `WatchedHandle` | – | entfallen aus der API (F-028) |

Folge für Tests der Nutzer: `QueryTrooper` & Co. lassen sich nicht mehr mit `implements` mocken. Der vorgesehene Weg
ist `Accessor`/`KeyedAccessor` (Interfaces) und `FakeAccessor`. Das wird im README genannt.

## F-028 · Exportierte Interna

**Empfehlung (wie Audit):**
- Nicht mehr exportieren: `StatefulStreamController`, `KeyedStatefulStream`, `KeyedTrooperAccessor` (wird privat),
  `WatchedHandle`, `WatchedUpdateCallback`, `TlocSourceUpdateEvent`.
- Damit entfallen die Konstruktorparameter `streamController:`, `stream:` und `streamManager:` an allen Troopers und
  Controller-Fabriken. Die Felder `Trooper.streamController` und `KeyedTrooper.stream` werden `@internal`.
- Alias `ConflictPolicy` entfernen.
- `TlocSourceUpdateEvent` taucht weiter in `onTransition`/`BlocObserver` auf; die Dartdoc von `Tloc` erwähnt das.

## F-030 · Redundanzen und Stolperstellen

| # | Punkt | **Empfehlung** | Alternative |
|---|---|---|---|
| 1 | `executeOrder66()` | **entfernen** | – |
| 2 | `onInit`/`initialize`, `onPause`/`pause` … | **Template-Method beibehalten, Rollen festschreiben:** `initialize()`, `pause()`, `resume()`, `recover()`, `didChangeDependencies()`, `dispose()` sind die Treiber und werden `@nonVirtual`; Nutzer überschreiben nur die `@protected`-Hooks `onInit` … `onDispose`. Damit gibt es genau einen Override-Punkt pro Ereignis, und die Reihenfolge (Hook vor Kindern, Fehler-Aggregation) bleibt garantiert. | Hooks entfernen; Nutzer überschreiben die Treiber mit `@mustCallSuper` und rufen `super` selbst (Reihenfolge liegt dann beim Nutzer). |
| 3 | `TrooperConfig.queryConflictPolicy` | **entfernen** | – |
| 4 | Global veränderliche Defaults (`TrooperConfig.defaultConfig`, `setDefaultConfig`, `Trooper.defaultConfig/setDefaultConfig`, `KeyedTrooper.defaultConfig`) | **entfernen**; ohne `config:` gilt `const TrooperConfig()`; gemeinsame Defaults nur über `TrooperController(defaultConfig: …)` | – |
| 5 | `fetch`/`cancellableFetch` (und `action`/`cancellableAction`, `initialValue`/`initialValueFactory`) nur per `assert` | **getrennte Fabriken:** `query` + `cancellableQuery`, `keyedQuery` + `cancellableKeyedQuery`, `mutation` + `cancellableMutation`, `keyedLocal` + `keyedLocalBuilder` (analog zu `KeyedLocalTrooper.builder`). Der jeweilige Callback wird `required`. | ein Parameter mit Union-Typ (gibt es in Dart nicht sauber) |
| 6 | Vier Wege zur Key-Adressierung | **`key()` entfernen.** `trooper[k]` ist der Weg für Konsumenten (liefert `Accessor`); die `*Key`-Methoden bleiben die Primitive am Trooper (für schreibende Operationen wie `setKey` ohnehin nötig). `KeyedLocalTrooper.currentKeyState` heißt künftig `currentKey` wie bei den anderen Keyed-Troopers. | zusätzlich lesende `*Key`-Methoden (`getKey`, `watchKey`, `currentKey` …) intern machen; dann nur noch `trooper[k].get(())` |
| 7 | `getMany` nur an `KeyedQueryTrooper` | **so lassen.** Methoden an `final`-Klassen später zu ergänzen ist nicht breaking; die Asymmetrie ist nicht freeze-relevant. | an allen Keyed-Troopers ergänzen |
| + | Zusätzlich gefunden: `Trooper.call()` liefert `accessor`, `TrooperMutation.call(P)` führt aus | **`Trooper.call()` entfernen**, `accessor` bleibt der einzige Weg. Sonst bedeutet `x()` je nach Typ etwas anderes. | behalten |

## F-033 · Re-Export-Strategie von `trooper_bloc`

| Option | Folge |
|---|---|
| **A: `package:trooper/trooper.dart` weiter vollständig re-exportieren, Versionsregel festschreiben** | Nutzer brauchen einen Import. Regel: `trooper_bloc` hängt von `trooper: ^1.x` ab; ein Major von `trooper` erzwingt einen Major von `trooper_bloc`; Minor/Patch von `trooper` sind für `trooper_bloc` additiv. Beide Packages tragen dieselbe Major-Version. |
| B: nur BLoC-Symbole exportieren | Nutzer importieren beide Packages; `trooper_bloc` ist von der API von `trooper` entkoppelt. |

**Empfehlung A**, Regel in beiden READMEs und im CHANGELOG. In beiden Fällen: `Emitter` (`flutter_bloc`) und
`FutureOr` (`dart:async`) **nicht mehr re-exportieren**. Wer `Emitter` in Handler-Signaturen schreibt, importiert
`package:flutter_bloc/flutter_bloc.dart` ohnehin für `BlocProvider`. Der Typ-Alias `Emit<State>` bleibt (das Inventar
schlug eine Umbenennung wegen der Nähe zu `Emitter` vor; ohne Re-Export entfällt die Verwechslung im selben Namensraum).

## F-022 / F-035 · `sealed` bei `TrooperException` und `TrooperEvent`

| Option | Exhaustive `switch` beim Nutzer | Neue Subtypen nach 1.0 | Fremde Subtypen |
|---|---|---|---|
| `sealed` (heute) | ja | Breaking | nein |
| `abstract base` (Audit-Vorschlag F-035) | nein | additiv | **ja**, Nutzer können eigene Events/Exceptions ableiten |
| **`abstract final`** | nein | additiv | nein |

**Empfehlung `abstract final` für beide** (alle Subtypen liegen in derselben Datei, `final` erlaubt das). Die Kataloge
bleiben geschlossen, wachsen aber ohne Major. Dazu:
- **`TrooperCodecException` jetzt ergänzen** (F-022): Encode-/Decode-Fehler beim L2-Zugriff erscheinen in
  `PersistenceErrorEvent.error` als `TrooperCodecException` (mit Original-Fehler in `error`), Backend-Fehler als
  `TrooperStorageException`. Damit sind beide unterscheidbar.
- Dartdoc an beiden Basisklassen: „Neue Subtypen können in Minor-Releases hinzukommen; `switch` braucht einen
  Default-Zweig.“

## F-034 · `DataLoaded`

**Empfehlung (wie Audit): `final class DataLoaded`.** `DataRefreshing` liegt in derselben Datei und darf weiter
ableiten. `WatchedHandle` wird intern (F-028).

## F-038 · Vertrag von `StorageBackend`

| Punkt | **Empfehlung** | Alternative |
|---|---|---|
| Methoden | **`read`, `write`, `delete`, `getAllKeys`**; `clear()` und `containsKey()` entfallen (von der Bibliothek nie gerufen; ein backendweites `clear()` ist gefährlich, wenn das Backend mit App-Daten geteilt wird) | `getAllKeys` durch `deleteWhere(String prefix)` ersetzen (effizienter für SQL-Backends, aber mehr Logik im Adapter) |
| Rückgabe `delete` | **`Future<void>`** (der alte Wert wird nirgends gebraucht) | `Future<String?>` behalten |
| Fehlervertrag | **dokumentieren:** Methoden dürfen werfen; Trooper fängt jeden Fehler, meldet ihn als `PersistenceErrorEvent` mit `TrooperStorageException` und arbeitet ohne L2 weiter | – |
| Nebenläufigkeit | **dokumentieren:** Aufrufe können parallel eintreffen, auch für denselben Key; Trooper wartet nur bei Purges (`invalidate`/`clearAll`), bis alle Deletes durch sind | – |
| Geteiltes Backend | **dokumentieren:** Trooper liest und löscht nur Keys mit seinem Präfix (`QueryKey.storagePrefix`) | – |
| Modifier | **`abstract interface` bleibt**; künftige Fähigkeiten kommen als zusätzliches optionales Interface, das per `is` geprüft wird | `abstract class` mit Default-Implementierungen |
| Contract-Test-Kit | **nicht in 1.0**: Das Kit ist additiv und nicht freeze-relevant. Es bräuchte `package:test` als reguläre Abhängigkeit von `trooper`; besser später als eigenes Package (`trooper_test`). `InMemoryStorageBackend` bleibt Referenz. | `package:trooper/testing.dart` mit `storageBackendContractTests()` jetzt, `test` wird reguläre Abhängigkeit |

## F-016 · Verhalten nach `dispose`

Heute uneinheitlich (StateError, stilles Weiterlaufen, `TrooperCancelledException`, Hängen).

**Empfehlung, für alle `LifecycleAware`-Typen der Bibliothek und `CacheStore`, festgeschrieben in der Dartdoc von
`LifecycleAware`:**

| Aufruf nach `dispose()` | Verhalten |
|---|---|
| Alles, was lädt, schreibt, emittiert, verbindet oder beobachtet (`get`, `refresh`, `trigger`, `set*`, `update*`, `reset*`, `connect*`, `execute`/`call`, `watch*`, `CacheStore.put/get…`) | **wirft synchron `StateError`** (bei `Future`-Methoden als fehlschlagendes `Future`) |
| `dispose()` | idempotent, kein Fehler |
| `isDisposed`, `current()`, `currentData()`, `currentStates`, `lastParam` | liefern den letzten Stand |
| `invalidate()`, `pause()`, `resume()`, `recover()`, `didChangeDependencies()` | **No-op.** Grund: `invalidateOnSuccess` und Controller-Kaskaden sollen nicht scheitern, weil ein Ziel schon entsorgt ist |

Die fünf `skip: 'F-016'`-Tests in `test/audit/lifecycle_audit_test.dart` werden aktiviert; dazu kommen Tests für die
No-op-Zeile.

---

## Bereits im Korrektheits-Paket hinzugekommen (wird mit eingefroren)

`RetryPolicy.jitter`/`defaultJitter`, `CacheStore(maxEntries)`, `ConsoleTrooperLogger(logParameters)`,
`releaseUnwatchedKeys` (Keyed-Troopers und Controller-Fabriken), geschützte `StorageAccess`-Helfer. Keine weitere
Entscheidung nötig; sie werden nur mit den Modifiern oben abgeglichen (`StorageAccess`-Helfer werden `@internal`).

## Danach

Doku, Skills und Beispiele angleichen; Baseline mit `dart_apitool extract` nach `docs/api/` (`doc/api/` ist per `.gitignore` ausgeschlossen);
Migrationsabschnitt im CHANGELOG beider Packages.
