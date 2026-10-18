# Audit Findings

Format nach Spec 6.2. Sortierung bis zur Konsolidierung in Task 13: nach Vergabe.
Maschinenlesbarer Status: `docs/audit/criteria.yaml` (Liste `findings`).

### F-001 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** QUAL-01
**Ort:** `analysis_options.yaml:1` (`include: package:lints/recommended.yaml`)
**Befund:** Die Packages werden nur gegen `lints/recommended` analysiert. Mit `very_good_analysis` und
`strict-casts`/`strict-inference`/`strict-raw-types` meldet der Analyzer 970 Issues: 614 in `lib/`, 292 in `test/`,
64 in `example/` und `benchmark/`. In `lib/` sind alle Treffer INFO-Level, es gibt keine Warnungen oder Fehler.
Größte Kategorien in `lib/`: `lines_longer_than_80_chars` 448 (überwiegend Doc-Kommentare; `dart format` ist sauber),
`public_member_api_docs` 41 (→ F-002), `avoid_catches_without_on_clauses` 40 (→ ERR-02, Task 9),
`comment_references` 24 (→ F-002), `directives_ordering` 20, `discarded_futures` 12 und `unawaited_futures` 2
(→ ASYNC-03, Task 7). In `test/` zusätzlich `inference_failure_on_function_invocation` (Warnung) und 84 `unawaited_futures`.
Das Root-README wirbt mit einem `very_good_analysis`-Badge; die Hypothese aus Spec §5 (QUAL-01) ist bestätigt.
**Nachweis:** `docs/audit/raw/analyze_vga.txt`, `docs/audit/raw/analyze_vga_summary.txt` (`tool/audit/scripts/static.sh`)
**Empfehlung:** `analysis_options.yaml` auf `very_good_analysis` + Strict-Modes umstellen, die Treffer kategorienweise
abarbeiten und den Analyzer-Lauf in die CI aufnehmen.

### F-002 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** DOC-01
**Ort:** `packages/trooper/lib/src/core/keyed_trooper.dart:137-234` (17 Member),
`packages/trooper/lib/src/telemetry/trooper_event.dart:14-126` (23 Member), `packages/trooper/lib/src/core/trooper.dart:50`
**Befund:** 41 öffentliche Member haben keine Dartdoc (`public_member_api_docs`). Dazu kommen 24 Doc-Kommentare mit
nicht auflösbaren Referenzen (`comment_references`), u. a. in `config/trooper_config.dart:56-70`,
`controller/trooper_controller.dart:60,207,209,574` und `trooper_bloc/lib/src/widgets/tloc_effect_listener.dart:9,40`.
Die Telemetrie-Events gehören zur Public API (OBS-01) und sind fast vollständig undokumentiert.
**Nachweis:** `docs/audit/raw/analyze_vga.txt` (Codes `PUBLIC_MEMBER_API_DOCS`, `COMMENT_REFERENCES`)
**Empfehlung:** Fehlende Dartdocs ergänzen, kaputte Referenzen korrigieren, `public_member_api_docs` als Fehler in
der CI erzwingen.

### F-003 · P1 · freeze-relevant: nein · Aufwand: L
**Kriterium:** TEST-01
**Ort:** `packages/trooper/lib/src/core/stream_trooper.dart` (69,8 %), `core/keyed_stream_trooper.dart` (71,3 %),
`core/keyed_query_trooper.dart` (71,5 %), `storage/cache_entry.dart` (76,0 %), `controller/trooper_controller.dart` (76,8 %),
`core/keyed_accessor.dart` (78,9 %), `core/keyed_trooper.dart` (79,6 %), `concurrency/mutation_queue.dart` (80,0 %)
**Befund:** `trooper` erreicht 83,7 % Line-Coverage (2.323/2.775) und 78,9 % Branch-Coverage (1.072/1.359). Das Gate
verlangt 95 % bzw. 85 %. `trooper_bloc` erfüllt die Schwelle mit 99,2 % Line- und 95,3 % Branch-Coverage.
Am schwächsten abgedeckt sind die Stream- und Keyed-Varianten sowie der Controller.
**Nachweis:** `docs/audit/raw/coverage_summary.txt`, `docs/audit/raw/coverage_trooper/lcov.info` (`tool/audit/scripts/tests.sh`)
**Empfehlung:** Tests für die genannten Dateien ergänzen, beginnend mit Fehler- und Dispose-Pfaden der Stream-Troopers;
Coverage-Schwelle in der CI erzwingen.

### F-004 · P2 · freeze-relevant: nein · Aufwand: M
**Kriterium:** TEST-03
**Ort:** `packages/trooper/test/core/stream_trooper_test.dart` (16 Stellen), `core/keyed_stream_trooper_test.dart` (12),
`edge_cases/swr_sequence_test.dart` (10), `stream/keyed_stateful_stream_test.dart` (8) u. a.
**Befund:** Beide Suiten liefen 100-mal mit zufälliger Reihenfolge ohne Fehler. Die Tests steuern Zeit aber an 121
Stellen mit echtem `Future.delayed`; `fake_async` ist als Dev-Dependency eingetragen, wird jedoch in keiner Testdatei
verwendet. Die Tests hängen damit von realen Laufzeiten ab (z. B. 50 ms vs. 10 ms in `out_of_order_test.dart`) und
können auf langsamen CI-Runnern kippen; zudem verlängern sie die Laufzeit.
**Nachweis:** `docs/audit/raw/flake_trooper.txt`, `docs/audit/raw/flake_trooper_bloc.txt`, `docs/audit/raw/real_delays.txt`
**Empfehlung:** Zeitabhängige Tests auf `fakeAsync` oder `Completer` umstellen.

### F-005 · P2 · freeze-relevant: nein · Aufwand: S
**Kriterium:** COMPAT-01
**Ort:** `packages/trooper/pubspec.yaml` (`dev_dependencies`), `pubspec.yaml` (Workspace)
**Befund:** Mit allen Abhängigkeiten auf ihrer Untergrenze (`flutter pub downgrade`) lassen sich die Tests von
`trooper` nicht mehr laden: `frontend_server_client` 3.2.0 sucht einen Snapshot, den Dart 3.13 nicht mehr enthält.
Betroffen ist nur die Dev-Toolchain; mit den Laufzeit-Abhängigkeiten auf ihrer Untergrenze (`meta` 1.19.0, `bloc` 9.0.0,
`flutter_bloc` 9.1.1) laufen beide Suiten grün. Die SDK-Untergrenze `^3.12.0` ist ungetestet, lokal ist nur Dart 3.13.5
verfügbar und es gibt keine CI-Matrix.
**Nachweis:** `docs/audit/raw/downgrade_trooper.txt`, `downgrade_versions.txt`, `downgrade_runtime_*.txt`
(`tool/audit/scripts/compat.sh`)
**Empfehlung:** Untergrenzen der Dev-Dependencies anheben (`test`, `coverage`), Min-SDK-Job in der CI ergänzen.

### F-006 · P2 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ARCH-02
**Ort:** `packages/trooper/lib/src/telemetry/telemetry_hub.dart`, `packages/trooper/lib/src/telemetry/trooper_logger.dart`
**Befund:** Der Import-Graph von `trooper` ist nicht azyklisch: `telemetry_hub.dart` und `trooper_logger.dart`
importieren sich gegenseitig. Alle übrigen 40 Dateien sind zyklenfrei, `trooper_bloc` ebenfalls. Eine Schichtregel
(welches Modul darf welches importieren) ist nirgends definiert oder automatisiert geprüft.
**Nachweis:** `docs/audit/raw/lakos_trooper.json` (`isAcyclic: false`, `firstCycle`), `tool/audit/scripts/api_arch.sh`
**Empfehlung:** Zyklus auflösen (Logger hängt vom Hub ab, nicht umgekehrt), Schichtregel dokumentieren und
`lakos --no-cycles-allowed` in die CI aufnehmen.

### F-007 · P2 · freeze-relevant: nein · Aufwand: L
**Kriterium:** ARCH-03
**Ort:** `controller/trooper_controller.dart` (869 Zeilen), `core/keyed_stream_trooper.dart` (807), `core/stream_trooper.dart` (632),
`core/keyed_query_trooper.dart` (606), `core/keyed_local_trooper.dart` (589), alle unter `packages/trooper/lib/src/`
**Befund:** Fünf Dateien überschreiten 500 Zeilen, ohne dass eine Begründung dokumentiert ist. Die Hypothese aus Spec §5
ist bestätigt. Die Größe korreliert mit der Duplikation zwischen Keyed- und Non-Keyed-Varianten (ARCH-04, Task 11) und
mit den komplexesten Methoden (F-008).
**Nachweis:** `docs/audit/raw/file_sizes.txt`
**Empfehlung:** Gemeinsame Fetch-/Cache-/Persistenz-Logik extrahieren; der Controller kann Fabrikmethoden und
Lifecycle-Verwaltung trennen.

### F-008 · P2 · freeze-relevant: nein · Aufwand: M
**Kriterium:** QUAL-03
**Ort:** `StreamTrooper.connect` (26), `QueryTrooper._executeFetch` (25), `KeyedStreamTrooper.getKey` (25),
`StreamTrooper.get`, `QueryTrooper.get`, `KeyedStreamTrooper.connectKey`, `KeyedQueryTrooper.getKey`,
`TrooperController.dispose` (je 24), `KeyedQueryTrooper._executeFetch`, `TrooperQueryQueue.execute` (je 22) und fünf weitere
**Befund:** 15 Methoden in `trooper` überschreiten eine zyklomatische Komplexität von 15; `trooper_bloc` hat keine.
Betroffen sind genau die Kernpfade für Lesen, Fetch und Dispose, in denen die Nebenläufigkeitsgarantien liegen.
**Nachweis:** `docs/audit/raw/metrics_trooper.json` (`dart_code_linter`, Schwelle 15)
**Empfehlung:** L1-, L2- und Netzwerkpfad in `get` jeweils in eigene Methoden zerlegen; Persistenzblock aus
`_executeFetch` herauslösen (er ist in `set` und `_executeFetch` doppelt vorhanden).
