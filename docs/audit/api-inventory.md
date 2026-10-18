# Public-API-Inventar

Grundlage: `docs/audit/raw/api_trooper.json`, `api_trooper_bloc.json` (`dart_apitool extract`) und
`docs/audit/raw/class_modifiers.txt`. „freeze-relevant: ja“ heißt: Eine spätere Änderung an diesem Symbol ist ein
Breaking Change. Spalte „Modifier jetzt“ zeigt `fehlt`, wenn die Klasse weder `final`, `base`, `interface` noch `sealed` trägt.

## `trooper`

| Symbol | Datei | Member | Modifier jetzt | Entscheidung | Begründung | Modifier-Vorschlag | freeze-relevant |
|---|---|---|---|---|---|---|---|
| `TrooperCodec` | `codec/trooper_codec.dart` | 9 | fehlt | behalten | Erweiterungspunkt für eigene Serialisierung | abstract base class | ja |
| `TrooperCancelToken` | `concurrency/cancel_token.dart` | 7 | fehlt | behalten | wird an Fetch-Funktionen übergeben | final class | ja |
| `TrooperMutationQueue` | `concurrency/mutation_queue.dart` | 11 | fehlt | behalten | teilbare Schreib-Queue (Controller-Injection) | final class | ja |
| `LifecycleAware` | `lifecycle/lifecycle_aware.dart` | 7 | fehlt | behalten | Vertrag für Lifecycle-Teilnehmer; `abstract mixin class` ist bewusst | – (abstract mixin) | ja |
| `TrooperQueryQueue` | `concurrency/query_queue.dart` | 15 | fehlt | behalten | teilbare Request-Queue für Coalescing über Troopers | final class | ja |
| `QueryConflictPolicy` | `config/query_conflict_policy.dart` | 4 | ok | behalten | Konfiguration | – (enum) | ja |
| `RetryPolicy` | `config/retry_policy.dart` | 13 | fehlt | behalten | Konfiguration; Jitter fehlt (F-023) | final class | ja |
| `StalePolicy` | `config/stale_policy.dart` | 3 | ok | behalten | Konfiguration | – (enum) | ja |
| `TrooperConfig` | `config/trooper_config.dart` | 15 | fehlt | umbauen | doppelter Getter `queryConflictPolicy`/`conflictPolicy`; global veränderliche Defaults `defaultConfig`/`setDefaultConfig` | final class | ja |
| `StorageBackend` | `storage/storage_backend.dart` | 7 | ok | behalten | Erweiterungspunkt L2; Vertrag dokumentieren (ARCH-05) | – (abstract interface) | ja |
| `TrooperController` | `controller/trooper_controller.dart` | 39 | fehlt | umbauen | `executeOrder66()` als Alias von `clearAll()`; doppelte Lifecycle-Namen (`onInit`/`initialize`, `onPause`/`pause` …); Fabriken mit zwei optionalen, sich ausschließenden Fetch-Parametern | abstract base class | ja |
| `Invalidatable` | `storage/invalidatable.dart` | 2 | ok | behalten | Vertrag für `invalidateOnSuccess` | – (abstract interface) | ja |
| `CacheStore` | `storage/cache_store.dart` | 28 | fehlt | behalten | teilbarer L1-Cache | final class | ja |
| `DataSource` | `state/data_metadata.dart` | 5 | ok | behalten | Metadaten | – (enum) | ja |
| `CacheEntry` | `storage/cache_entry.dart` | 15 | fehlt | behalten | über `CacheStore.getEntry/putEntry` sichtbar | final class | ja |
| `DataMetadata` | `state/data_metadata.dart` | 10 | fehlt | behalten | Teil von `DataLoaded` | final class | ja |
| `TelemetryHub` | `telemetry/telemetry_hub.dart` | 13 | fehlt | behalten | Observability | final class | ja |
| `TrooperEvent` | `telemetry/trooper_event.dart` | 2 | ok | umbauen | `sealed`: jedes neue Event nach 1.0 bricht exhaustive `switch` (F-020 braucht z. B. ein neues Event) | abstract base class (nicht sealed) | ja |
| `TrooperLogger` | `telemetry/trooper_logger.dart` | 2 | ok | behalten | Erweiterungspunkt | – (abstract interface) | ja |
| `TrooperSideEffects` | `effects/trooper_side_effects.dart` | 9 | fehlt | behalten | Konfiguration | final class | ja |
| `StatefulStreamController` | `stream/stateful_stream_controller.dart` | 23 | fehlt | intern machen | als Konstruktorparameter injizierbar; erlaubt fremdes Emittieren in den State eines Troopers | – (nicht exportieren) | ja |
| `StatefulData` | `state/stateful_data.dart` | 17 | ok | behalten | zentrales Zustandsmodell | – (sealed) | ja |
| `StatefulStream` | `stream/stateful_stream.dart` | 15 | fehlt | behalten | Rückgabetyp von `watch`/`stream` | final class | ja |
| `QueryTrooper` | `core/query_trooper.dart` | 36 | fehlt | behalten | Kern-API | final class | ja |
| `Trooper` | `core/trooper.dart` | 33 | fehlt | behalten | Basisklasse; `@protected`-Member werden Teil des Vertrags | abstract base class | ja |
| `Accessor` | `core/accessor.dart` | 9 | ok | behalten | lesende Fassade, Grundlage für Tests (`FakeAccessor`) | – (abstract interface) | ja |
| `KeyedTrooperSideEffects` | `effects/trooper_keyed_side_effects.dart` | 9 | fehlt | behalten | Konfiguration | final class | ja |
| `KeyedStatefulStream` | `stream/keyed_stateful_stream.dart` | 29 | fehlt | intern machen | analog `StatefulStreamController` als Konstruktorparameter `stream` injizierbar | – (nicht exportieren) | ja |
| `KeyedQueryTrooper` | `core/keyed_query_trooper.dart` | 57 | fehlt | behalten | Kern-API; `getMany` fehlt den anderen Keyed-Varianten | final class | ja |
| `KeyedTrooper` | `core/keyed_trooper.dart` | 48 | fehlt | behalten | Basisklasse | abstract base class | ja |
| `KeyedAccessor` | `core/keyed_accessor.dart` | 22 | ok | behalten | lesende Fassade | – (abstract interface) | ja |
| `LoadMore` | `pagination/load_more.dart` | 22 | fehlt | behalten | Pagination | final class | ja |
| `LocalTrooper` | `core/local_trooper.dart` | 40 | fehlt | behalten | Kern-API | final class | ja |
| `KeyedLocalTrooper` | `core/keyed_local_trooper.dart` | 69 | fehlt | behalten | Kern-API; 52 Member, größte Oberfläche | final class | ja |
| `StreamTrooper` | `core/stream_trooper.dart` | 44 | fehlt | behalten | Kern-API | final class | ja |
| `KeyedStreamTrooper` | `core/keyed_stream_trooper.dart` | 65 | fehlt | behalten | Kern-API | final class | ja |
| `TrooperMutationSideEffects` | `effects/trooper_mutation_side_effects.dart` | 4 | fehlt | behalten | Konfiguration | final class | ja |
| `TrooperMutation` | `core/trooper_mutation.dart` | 21 | fehlt | behalten | Kern-API | final class | ja |
| `ParameterlessAccessor` | `core/accessor.dart` | 4 | ok | behalten | Ergonomie für `()`-Parameter | – (extension) | ja |
| `KeyedTrooperAccessor` | `core/keyed_accessor.dart` | 27 | fehlt | intern machen | konkrete Implementierung von `KeyedAccessor`; Nutzer brauchen nur das Interface | – (nicht exportieren) | ja |
| `ParameterlessKeyedAccessor` | `core/keyed_accessor.dart` | 4 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessKeyedLocalTrooper` | `core/keyed_local_trooper.dart` | 15 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessKeyedStreamTrooper` | `core/keyed_stream_trooper.dart` | 11 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessKeyedQueryTrooper` | `core/keyed_query_trooper.dart` | 9 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessLocalTrooper` | `core/local_trooper.dart` | 4 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessStreamTrooper` | `core/stream_trooper.dart` | 1 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessTrooper` | `core/trooper.dart` | 1 | ok | behalten | Ergonomie | – (extension) | ja |
| `ParameterlessTrooperMutation` | `core/trooper_mutation.dart` | 2 | ok | behalten | Ergonomie | – (extension) | ja |
| `TrooperException` | `error/trooper_exception.dart` | 4 | ok | prüfen | `sealed`; `TrooperCodecException` fehlt (F-022) | – (sealed) | ja |
| `TrooperCancelledException` | `error/trooper_exception.dart` | 4 | ok | behalten | Fehlertyp | – (final) | ja |
| `TrooperTimeoutException` | `error/trooper_exception.dart` | 5 | ok | behalten | Fehlertyp | – (final) | ja |
| `TrooperStorageException` | `error/trooper_exception.dart` | 4 | ok | behalten | Fehlertyp | – (final) | ja |
| `LoadMoreData` | `pagination/load_more.dart` | 11 | ok | behalten | Zustand der Pagination | – (final) | ja |
| `LoadMoreItems` | `pagination/load_more.dart` | 1 | ok | behalten | Hilfs-Extension | – (extension) | ja |
| `DataInitial` | `state/stateful_data.dart` | 13 | ok | behalten | Zustand | – (final) | ja |
| `DataLoading` | `state/stateful_data.dart` | 14 | ok | behalten | Zustand | – (final) | ja |
| `DataLoaded` | `state/stateful_data.dart` | 15 | ok | umbauen | `base` erlaubt Subklassen außerhalb der Bibliothek; `final` reicht, weil `DataRefreshing` in derselben Bibliothek liegt | final class | ja |
| `DataRefreshing` | `state/stateful_data.dart` | 16 | ok | behalten | Zustand | – (final) | ja |
| `DataError` | `state/stateful_data.dart` | 16 | ok | behalten | Zustand | – (final) | ja |
| `InMemoryStorageBackend` | `storage/storage_backend.dart` | 8 | fehlt | behalten | Referenz-Backend für Tests | final class | ja |
| `StorageEnvelope` | `storage/storage_envelope.dart` | 16 | fehlt | behalten | persistentes L2-Format; Versionierung fehlt (F-024) | final class | ja |
| `RequestStartedEvent` | `telemetry/trooper_event.dart` | 3 | ok | behalten | Telemetrie | – (final) | ja |
| `CacheHitEvent` | `telemetry/trooper_event.dart` | 5 | ok | behalten | Telemetrie | – (final) | ja |
| `SWRTriggeredEvent` | `telemetry/trooper_event.dart` | 3 | ok | behalten | Telemetrie | – (final) | ja |
| `RequestCompletedEvent` | `telemetry/trooper_event.dart` | 5 | ok | behalten | Telemetrie | – (final) | ja |
| `RequestErrorEvent` | `telemetry/trooper_event.dart` | 6 | ok | behalten | Telemetrie | – (final) | ja |
| `PersistenceErrorEvent` | `telemetry/trooper_event.dart` | 6 | ok | behalten | Telemetrie | – (final) | ja |
| `CacheInvalidatedEvent` | `telemetry/trooper_event.dart` | 3 | ok | behalten | Telemetrie | – (final) | ja |
| `DataSetEvent` | `telemetry/trooper_event.dart` | 4 | ok | behalten | Telemetrie | – (final) | ja |
| `ConsoleTrooperLogger` | `telemetry/trooper_logger.dart` | 5 | fehlt | behalten | Standard-Logger; maskiert keine Parameter (F-027) | final class | ja |

Typ-Aliase:

| Alias | Entscheidung | Begründung | freeze-relevant |
|---|---|---|---|
| `ConflictPolicy` | entfernen | zweiter Name für `QueryConflictPolicy` | ja |
| `KeyedStreamFactory` | behalten | Signatur der Stream-Fabrik | ja |
| `StreamFactory` | behalten | Signatur der Stream-Fabrik | ja |
| `Parameter` | behalten | Alias für `Record`; liegt als einzige Datei außerhalb von `src/` (`lib/types/parameter.dart`) | ja |

## `trooper_bloc`

| Symbol | Datei | Member | Modifier jetzt | Entscheidung | Begründung | Modifier-Vorschlag | freeze-relevant |
|---|---|---|---|---|---|---|---|
| `FakeAccessor` | `lib/testing.dart` | 14 | fehlt | behalten | Test-Utility (`testing.dart`) | final class | ja |
| `Effects` | `effects/effects.dart` | 3 | ok | behalten | Presentation-Effects-Mixin | – (mixin) | ja |
| `TlocEvent` | `events.dart` | 1 | fehlt | behalten | Basis für Domain-Events | abstract base class | ja |
| `TlocSourceUpdateEvent` | `events.dart` | 2 | ok | intern machen | internes Plumbing-Event von `Tloc`; erscheint aber in `onTransition` – falls behalten, dokumentieren | – (final) | ja |
| `MatchResult` | `match_result.dart` | 5 | ok | behalten | Rückgabe von `matchSources` | – (enum) | ja |
| `TrooperSources` | `sources/trooper_sources.dart` | 14 | ok | behalten | Kern-Mixin für Ableitung | – (mixin) | ja |
| `Watched` | `sources/watched.dart` | 6 | ok | behalten | Rückgabetyp von `watch` | – (abstract interface) | ja |
| `WatchedHandle` | `sources/watched.dart` | 17 | fehlt | intern machen | Implementierung von `Watched`; einziger `dynamic`-Parameter der API | – (nicht exportieren) | ja |
| `Tloc` | `tloc.dart` | 18 | fehlt | behalten | Kern-API | abstract base class | ja |
| `Tubit` | `tubit.dart` | 17 | fehlt | behalten | Kern-API | abstract base class | ja |
| `TlocEffectListener` | `widgets/tloc_effect_listener.dart` | 5 | fehlt | behalten | Widget | – (Widget, offen lassen) | ja |

Typ-Aliase:

| Alias | Entscheidung | Begründung | freeze-relevant |
|---|---|---|---|
| `Emit` | umbenennen | kollidiert begrifflich mit dem re-exportierten `Emitter` aus `flutter_bloc` | ja |
| `WatchedUpdateCallback` | intern machen | gehört zu `WatchedHandle` | ja |
| `EffectWidgetListener` | behalten | Callback von `TlocEffectListener` | ja |

## Re-Exporte von `trooper_bloc`

| Re-Export | Entscheidung | Begründung |
|---|---|---|
| `package:trooper/trooper.dart` (vollständig) | Versionsregel festlegen | Jede Änderung an `trooper` wird zur Änderung an `trooper_bloc`; ohne Regel ist ein Minor-Release von `trooper` ein Breaking Change für `trooper_bloc` (API-06) |
| `Emitter` aus `flutter_bloc` | entfernen oder bewusst dokumentieren | bindet die SemVer an `flutter_bloc`; Nutzer importieren `flutter_bloc` ohnehin |
| `FutureOr` aus `dart:async` | entfernen | Re-Export eines SDK-Typs ohne Mehrwert |

## Weitere Punkte

- **Mehrfache Key-Adressierung:** `trooper['k']`, `key('k')`, `getKey`/`watchKey`/`currentKey`. Vier Wege für dasselbe vergrößern die eingefrorene Oberfläche.
- **Asymmetrie:** `getMany` existiert nur an `KeyedQueryTrooper`; `currentKeyState` nur an `KeyedLocalTrooper`.
- **`dynamic` in der API:** `TrooperCodec.json` und `StorageEnvelope.toJson/fromJson` (JSON-Maps, vertretbar), `WatchedHandle.new` (Callback, vermeidbar).
- **`@protected`-Member** in `Trooper`/`KeyedTrooper` (`recordParam`, `buildQueryKey`, `isParamChanged`, `runSideEffect`) werden mit `abstract base` Teil des Vertrags für Subklassen.

## Zusammenfassung

| Entscheidung | Anzahl |
|---|---|
| behalten | 75 |
| intern machen | 6 |
| umbauen | 4 |
| prüfen | 1 |
| entfernen | 1 |
| umbenennen | 1 |
