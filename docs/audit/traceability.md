# Feature-Traceability (FEAT-01)

Jeder Feature-Claim aus READMEs, Dartdoc und Agent-Skills mit dem Test, der ihn belegt.
Status: **belegt** (Test vorhanden und grün) · **teilweise** (belegt mit Einschränkung) · **fehlt** (kein Beleg) ·
**widerlegt** (Test oder Code widerspricht dem Claim). Testpfade relativ zu `packages/`.

| ID | Claim | Quelle | Beleg | Status |
|---|---|---|---|---|
| C-001 | Jeder Trooper verwaltet genau einen logischen Zustands-Slot (bzw. einen pro Key) | `README.md:75` | `trooper/test/edge_cases/out_of_order_test.dart` – „…prevent cache pollution“; `trooper/test/audit/async_audit_test.dart` – ASYNC-07 | teilweise (nur für Parameterwechsel und Default-Policy belegt) |
| C-002 | Zero-Flicker-SWR: Daten bleiben während des Hintergrund-Refresh sichtbar | `README.md:76`, `trooper/README.md:36` | `trooper/test/edge_cases/swr_sequence_test.dart`; `trooper/test/audit/feature_audit_test.dart` – FEAT-02 (Query, KeyedQuery, Stream) | belegt |
| C-003 | 50 gleichzeitige Requests auf denselben Slot teilen einen Netzwerkaufruf | `README.md:77` | `trooper/test/edge_cases/cache_stampede_test.dart` – „cold stampede: 500 …“; `feature_audit_test.dart` – FEAT-03 (2, 50, zwei Controller) | belegt |
| C-004 | Snapshot-Locking verhindert State-Tearing über `await` | `README.md:78` | `trooper_bloc/test/tloc_test.dart` – „snapshot-locking preserves …“; `trooper_bloc/test/audit/bloc_feature_audit_test.dart` | belegt |
| C-005 | Mehrere Source-Updates im selben Event-Loop ergeben eine UI-Transition | `README.md:79` | `trooper_bloc/test/audit/bloc_feature_audit_test.dart` – „two updates in one event loop …“ | belegt (nur durch Audit-Prüftest; die Suite des Packages prüft es nicht) |
| C-006 | One-off Presentation-Effects über `Effects<F>` und `TlocEffectListener` | `README.md:80` | `trooper_bloc/test/effects_test.dart`, `trooper_bloc/test/widgets/tloc_effect_listener_test.dart` | belegt |
| C-007 | Conflict-Policies `forward`, `cancel`, `parallel` | `README.md:81` | `trooper/test/core/query_trooper_test.dart` – „conflict policy …“ (3 Tests); `async_audit_test.dart` – ASYNC-01/02 | teilweise (`parallel`: F-012; `forward`: F-013) |
| C-008 | Exponentieller/linearer `RetryPolicy` und Timeouts | `README.md:82`, `trooper/README.md:37` | `trooper/test/config/retry_policy_test.dart`; `trooper/test/error/timeout_and_storage_test.dart`; `trooper/test/audit/error_audit_test.dart` – ERR-03 | belegt |
| C-009 | Batch-Operationen für alle Keyed-Varianten (`getAll`, `setAll`, `updateAll`, `resetKeys`, `connectKeys`, `disconnectKeys`) | `README.md:83` | `trooper/test/core/batch_keyed_operations_test.dart` | belegt |
| C-010 | „Telemetry & DevTools: structured, zero-allocation diagnostic events“ | `README.md:84` | `docs/audit/raw/telemetry_overhead.txt`; Code-Review | widerlegt („DevTools“: keine Integration vorhanden; „zero-allocation“ gilt nur ohne Listener) |
| C-011 | L1-Cache mit austauschbarem L2-Speicher und `StorageEnvelope` | `README.md:85` | `feature_audit_test.dart` – FEAT-05 (Kaltstart, Write-through); `async_audit_test.dart` – „invalidate removes L2 storage …“ | teilweise (Invalidierung von L2: F-014; Schlüsselkollision: F-060; Versionierung: F-024) |
| C-012 | Automatische Deduplizierung gleichzeitiger Requests | `trooper/README.md:35`, `:199-200` | `trooper/test/core/query_trooper_test.dart` – „deduplicates concurrent requests …“ | belegt |
| C-013 | Typsichere Records als Parameter | `trooper/README.md:39` | Typsystem (`typedef Parameter = Record`) | belegt (statisch durch den Compiler) |
| C-014 | Controller räumen beim `dispose` alle Subscriptions, Watcher und Cancel-Tokens auf | `trooper/README.md:40` | `trooper/test/audit/lifecycle_audit_test.dart` – LIFE-04; `trooper/test/edge_cases/controller_disposal_in_flight_test.dart` | teilweise (`KeyedStreamTrooper.dispose`: F-017) |
| C-015 | Mutationen laufen sequenziell (FIFO) und invalidieren deklarativ | `trooper/README.md:156`, `:212-213` | `trooper/test/concurrency/mutation_queue_test.dart` – „enforces strict FIFO …“; `async_audit_test.dart` – ASYNC-06 | belegt |
| C-016 | Queries und Mutationen unterstützen `TrooperCancelToken`; „cancel the token“, wenn der Nutzer den Screen verlässt | `trooper/README.md:202-210` | Code-Review: `Accessor.get`/`refresh` nehmen kein Token entgegen; `async_audit_test.dart` – „ASYNC-05 TrooperMutation …“ | widerlegt (Queries können kein eigenes Token erhalten; Mutation ignoriert den Abbruch: F-015) |
| C-017 | Load-More / Infinite Scroll | `trooper/README.md:254` | `trooper/test/pagination/load_more_test.dart`; `trooper_bloc/test/sources/load_more_tloc_test.dart` | belegt |
| C-018 | `TelemetryHub.global.addListener(...)` | `trooper/README.md:330-336` | `docs/audit/raw/snippets_analyze.txt` | widerlegt (Methode existiert nicht) |
| C-019 | Paket `trooper_flutter` mit `TrooperBuilder` und `TrooperScope` | `trooper/README.md:376` | Repository | widerlegt (Paket existiert nicht) |
| C-020 | `parallel`: „Stream & Cache protected by sequence-ID“ | `trooper/lib/src/config/query_conflict_policy.dart:20,91` | `async_audit_test.dart` – „ASYNC-01 … parallel“ | widerlegt (F-012) |
| C-021 | `invalidate()` „removes storage“ | `trooper/lib/src/core/accessor.dart:58` | `async_audit_test.dart` – „invalidate removes L2 storage as documented“ | widerlegt (F-014) |
| C-022 | Parameterlose Kurzformen wie `accessor.get()`, `counter.set(10)`, `mutation()` | `trooper/skills/trooper-reactive-data-flow/SKILL.md:146,223`, `trooper_bloc/README.md:68`, Dartdoc der `Parameterless*`-Extensions | `docs/audit/raw/parameterless_shadowing.txt`; `snippets_analyze.txt` | widerlegt (alle 51 Extension-Member sind durch Instanzmethoden verdeckt: F-044) |
| C-023 | `TrooperMutationQueue` verhindert Race Conditions durch strikte Reihenfolge | `trooper/lib/src/concurrency/mutation_queue.dart:5-8` | `mutation_queue_test.dart`; `async_audit_test.dart` – ASYNC-06 | belegt |
| C-024 | SWR-Garantie im BLoC: Refresh zeigt weiter Daten an | `trooper_bloc/README.md:137` | `trooper_bloc/test/audit/bloc_feature_audit_test.dart` – „C-024 DataRefreshing keeps showing data …“ | belegt (nur durch Audit-Prüftest; die Suite des Packages prüft `DataRefreshing` nicht) |
| C-025 | `FakeAccessor` für Unit-Tests | `trooper_bloc/README.md`, `trooper_bloc/skills/…/SKILL.md` | `trooper_bloc/test/testing_test.dart` (100 % Line- und Branch-Coverage) | belegt |
| C-026 | Beispiel `QueryTrooper(fetcher: …, cacheDuration: …)` | `trooper_bloc/skills/trooper-bloc-state-management/SKILL.md:510` | `snippets_analyze.txt` | widerlegt (Parameter heißen `fetch` und `config: TrooperConfig(timeToLive: …)`: F-043) |
| C-027 | `dart analyze` meldet 0 Errors, 0 Warnings, 0 Lints | `README.md:288` | `dart analyze packages` auf `main` mit `lints/recommended` | belegt (mit `very_good_analysis` nicht: F-001) |
| C-028 | Unterstützt Dart 3.5+ (Badge) | `README.md:5` | `packages/*/pubspec.yaml` (`sdk: ^3.12.0`) | widerlegt (F-045) |
| C-029 | Stil „very good analysis“ (Badge) | `README.md:8` | `analysis_options.yaml` | widerlegt (F-001) |
| C-030 | `Tloc`/`Tubit` leiten State reaktiv aus `watch()`-Quellen ab | `README.md:169-238`, `trooper_bloc/README.md` | `trooper_bloc/test/tloc_test.dart`, `tubit_test.dart` | belegt (Codebeispiele kompilieren nicht: F-043) |

## Zusammenfassung

| Status | Anzahl |
|---|---|
| belegt | 16 |
| teilweise | 4 |
| widerlegt | 10 |
| fehlt | 0 |
