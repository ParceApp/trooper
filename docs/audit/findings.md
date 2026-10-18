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
**Nachweis:** `docs/audit/raw/analyze_vga.txt` (Codes `PUBLIC_MEMBER_API_DOCS`, `COMMENT_REFERENCES`); `docs/audit/raw/dartdoc_bloc.txt` (3 unaufgelöste Referenzen: `[super.add]`, `[effects]`, `[context.read]`)
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

### F-009 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** REL-01
**Ort:** `packages/trooper_bloc/CHANGELOG.md:1`, `packages/trooper_bloc/pubspec.yaml` (`version: 0.1.2-beta.1`)
**Befund:** `trooper` erreicht bei pana 160/160, der Dry-Run meldet 0 Warnungen. Für `trooper_bloc` meldet der Dry-Run
eine Warnung: Der CHANGELOG nennt die aktuelle Version 0.1.2-beta.1 nicht (er beginnt bei 0.1.0-beta.1). pana vergibt
45/160, weil `trooper` auf pub.dev nicht existiert (beide Packages sind noch unveröffentlicht, HTTP 404) und damit
Analyse, Dartdoc, Plattform- und Downgrade-Prüfung nicht laufen. Eine belastbare pana-Bewertung von `trooper_bloc` ist
erst nach dem Release von `trooper` möglich.
**Nachweis:** `docs/audit/raw/dryrun_bloc.txt`, `docs/audit/raw/pana_trooper_bloc.txt`, `docs/audit/raw/pana_summary.txt`
**Empfehlung:** CHANGELOG-Eintrag für 0.1.2-beta.1 ergänzen; Release-Reihenfolge festlegen (erst `trooper`, dann
`trooper_bloc`) und pana für `trooper_bloc` danach erneut laufen lassen, bis dahin in der CI mit `dependency_overrides`.

### F-010 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** REL-03
**Ort:** `packages/trooper_bloc/skills/trooper-bloc-state-management/SKILL.md:56-62` (7 Links),
`packages/trooper/example/README.md` (2 Links)
**Befund:** Dateien, die im Paketarchiv ausgeliefert werden, verlinken auf lokale Pfade `file:///Users/hannes/Developer/trooper/...`.
Die Links funktionieren für niemanden außer auf dem Entwicklerrechner und geben den lokalen Benutzernamen preis.
Das Root-README hat 11 weitere solcher Links (→ DOC-02, Task 12). Sonst ist der Paketinhalt angemessen: Das 1-MB-GIF
in `packages/trooper/doc/` wird vom README eingebunden.
**Nachweis:** `grep -n "file:///"` auf die ausgelieferten Dateien; Dateilisten in `docs/audit/raw/dryrun_*.txt`
**Empfehlung:** Relative Links oder GitHub-URLs verwenden; einen Linkcheck gegen `file://` in die CI aufnehmen.

### F-011 · P2 · freeze-relevant: nein · Aufwand: M
**Kriterium:** PERF-02
**Ort:** `packages/trooper/benchmark/trooper_benchmark.dart`
**Befund:** Eine Baseline liegt jetzt vor (Median aus drei Läufen, `bench_baseline.txt`), aber die Läufe streuen stark:
Im zweiten Lauf lagen alle vier Benchmarks 20–70 % unter den anderen beiden (z. B. Request-Coalescing 45.983 statt
~131.000 ops/s). Mit dieser Streuung ist eine 10-%-Regressionsschranke nicht belastbar. Eine CI-Prüfung fehlt ganz.
**Nachweis:** `docs/audit/raw/bench_run1.txt` … `bench_run3.txt`, `docs/audit/raw/bench_baseline.txt`
**Empfehlung:** Warm-up und mehrere Messwiederholungen pro Benchmark (z. B. `benchmark_harness`), Median und Streuung
ausgeben; Regressionsprüfung erst auf dieser Basis in die CI aufnehmen.

### F-012 · P0 · freeze-relevant: nein · Aufwand: M
**Kriterium:** ASYNC-01
**Ort:** `packages/trooper/lib/src/concurrency/query_queue.dart:110` (`case QueryConflictPolicy.parallel`),
`packages/trooper/lib/src/core/query_trooper.dart:313`, analog `keyed_query_trooper.dart`
**Befund:** Mit `QueryConflictPolicy.parallel` überschreibt eine ältere Antwort eine neuere: Zwei Fetches auf denselben
Slot laufen parallel; antwortet der zuerst gestartete zuletzt, landet sein veraltetes Ergebnis in Stream, L1-Cache und
L2-Speicher. Die einzige Schutzbedingung in `_executeFetch` ist `!isParamChanged(param)`, die bei gleichem Parameter
nichts verhindert. Die Dartdoc verspricht ausdrücklich das Gegenteil: „Stream & Cache: Protected by sequence-ID“
(`query_conflict_policy.dart:20`, `:91`); eine Sequence-ID existiert im Code nicht. Betroffen sind `QueryTrooper`
und `KeyedQueryTrooper`; mit `cancel` und `forward` ist der Endzustand korrekt.
**Nachweis:** `packages/trooper/test/audit/async_audit_test.dart` – „ASYNC-01 … QueryConflictPolicy.parallel“ (2 Tests, rot)
**Empfehlung:** Pro Slot eine monoton steigende Request-Sequenz führen und nur Ergebnisse übernehmen, deren Sequenz
nicht älter als die zuletzt übernommene ist.

### F-013 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** ASYNC-02
**Ort:** `packages/trooper/lib/src/concurrency/query_queue.dart:107` (`_linkCompleter`) und `:137` (`completer.complete(result)`)
**Befund:** Mit der Default-Policy `forward` verspricht die Dartdoc, dass wartende Aufrufer „auf den neuen Request
weitergeleitet“ werden. Ignoriert der Fetch sein Cancel-Token (der Normalfall bei einfachen HTTP-Aufrufen) und
antwortet der überholte Request zuerst, erhält der erste Aufrufer trotzdem das alte Ergebnis, und dieses wird kurz in
Stream und Cache geschrieben, bevor das neue es ersetzt. Ursache: Der alte `runTask` vervollständigt seinen Completer
selbst, bevor der verlinkte neue Request fertig ist. Der Endzustand ist korrekt, die Zwischenzustände nicht.
**Nachweis:** `async_audit_test.dart` – „ASYNC-02 … refresh (forward): first caller receives the newer result“ (rot)
**Empfehlung:** Bei `forward` den Completer des überholten Requests ausschließlich über den neuen Request vervollständigen
und das Ergebnis des alten verwerfen.

### F-014 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ASYNC-02
**Ort:** `packages/trooper/lib/src/core/trooper.dart:172` (`invalidate`), `packages/trooper/lib/src/core/accessor.dart:58`,
`packages/trooper/lib/src/controller/trooper_controller.dart:651` (`clearAll`)
**Befund:** Laut Dartdoc „removes storage“ entfernt `invalidate()` auch den L2-Eintrag; tatsächlich bleibt er erhalten
und wird beim nächsten `get` wiederhergestellt. Auch `TrooperController.clearAll()` löscht persistierte Daten
nicht-keyed Troopers nicht. Ein Logout per `clearAll()` hinterlässt damit Nutzerdaten (im Test: eine E-Mail-Adresse)
auf der Platte, und der nächste Nutzer bekommt sie aus L2 angezeigt. Zusätzlich bricht `invalidate()` laufende
Requests mit `TrooperCancelledException` ab, was nirgends dokumentiert ist.
**Nachweis:** `async_audit_test.dart` – „invalidate removes L2 storage as documented“ und
„controller.clearAll removes persisted QueryTrooper data“ (beide rot)
**Empfehlung:** `invalidate()` und `clearAll()` löschen die zugehörigen Storage-Keys (oder die Doku wird korrigiert und
eine explizite `purge()`-API ergänzt); Abbruchverhalten dokumentieren.

### F-015 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ASYNC-05
**Ort:** `packages/trooper/lib/src/core/trooper_mutation.dart:134`
**Befund:** `TrooperMutation.execute` prüft das übergebene `TrooperCancelToken` nach Abschluss der Action nicht. Wird
die Mutation abgebrochen und liefert die Action trotzdem ein Ergebnis, emittiert sie `DataLoaded`, führt
`invalidateOnSuccess` aus und ruft `onSuccess` auf. `QueryTrooper` verhält sich korrekt (kein State nach Cancel).
**Nachweis:** `async_audit_test.dart` – „ASYNC-05 TrooperMutation: no DataLoaded after cancel“ (rot)
**Empfehlung:** Nach `await action(...)` das Token prüfen und bei Abbruch `TrooperCancelledException` werfen,
ohne State, Invalidierung oder Side-Effects auszulösen.

### F-016 · P1 · freeze-relevant: ja · Aufwand: M
**Kriterium:** LIFE-01
**Ort:** `packages/trooper/lib/src/core/local_trooper.dart:260`, `core/keyed_local_trooper.dart`, `core/stream_trooper.dart:431`,
`core/keyed_stream_trooper.dart:443`, `storage/cache_store.dart`; Vertrag in `lifecycle/lifecycle_aware.dart` („should not be reused“)
**Befund:** `dispose()` ist für alle elf geprüften Typen idempotent. Das Verhalten **nach** `dispose` ist aber weder
dokumentiert noch einheitlich: `QueryTrooper`, `KeyedQueryTrooper`, `TrooperMutation`, beide Queues und der Controller
werfen `StateError`; `LocalTrooper` und `KeyedLocalTrooper` liefern stillschweigend weiter Werte; `CacheStore` nimmt
weiter Einträge an; `StreamTrooper` wirft `TrooperCancelledException`; `KeyedStreamTrooper.getKey` kehrt **nie** zurück
(Test-Timeout nach 30 s). Ein nachträgliches Vereinheitlichen ändert beobachtbares Verhalten und ist nach dem Freeze
ein Breaking Change.
**Nachweis:** `packages/trooper/test/audit/lifecycle_audit_test.dart` – „LIFE-01 <Typ> use after dispose fails with StateError“
(5 Tests rot)
**Empfehlung:** Einheitlich `StateError` nach `dispose` werfen, im Vertrag von `LifecycleAware` dokumentieren und testen.

### F-017 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** LIFE-02
**Ort:** `packages/trooper/lib/src/core/keyed_stream_trooper.dart:718`
**Befund:** `KeyedStreamTrooper.dispose()` iteriert über `_subscriptions.values` und wartet dabei mit `await sub.cancel()`.
Verändert ein Callback die Map während dieses `await`, bricht `dispose()` mit `ConcurrentModificationError` ab. Die
restlichen Subscriptions werden dann nicht gekündigt, und `super.dispose()` (Stream-Controller, Queue, Cache) läuft
nicht. Unter `fakeAsync` ist das reproduzierbar, mit Echtzeit hängt es vom Timing ab.
**Nachweis:** `lifecycle_audit_test.dart` – „LIFE-02 KeyedStreamTrooper leaves no timers after dispose“ (rot, Stacktrace
`keyed_stream_trooper.dart 718:38`)
**Empfehlung:** Vor der Schleife eine Kopie ziehen (`List.of(_subscriptions.values)`), Map sofort leeren, dann kündigen.

### F-018 · P2 · freeze-relevant: nein · Aufwand: S
**Kriterium:** LIFE-02
**Ort:** `packages/trooper/lib/src/concurrency/query_queue.dart:151`
**Befund:** Der Backoff zwischen Retries ist ein nicht abbrechbares `Future.delayed`. Nach `dispose()` bleibt der Timer
bis zum Ablauf der Wartezeit aktiv (im Test: eine Minute) und hält Trooper und Closure so lange am Leben; erst danach
wird das Cancel-Token geprüft.
**Nachweis:** `lifecycle_audit_test.dart` – „LIFE-02 retry backoff timer does not outlive dispose“ (rot)
**Empfehlung:** Backoff über einen `Timer` umsetzen, der beim Abbruch des Cancel-Tokens gecancelt wird.

### F-019 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** LIFE-03
**Ort:** `packages/trooper/lib/src/storage/cache_store.dart:48` und `:34` (`evictionInterval` standardmäßig `null`),
`core/keyed_trooper.dart:75`, `stream/keyed_stateful_stream.dart:42`, `core/keyed_stream_trooper.dart:138-143`
**Befund:** Kein Speicher ist begrenzt. Der `CacheStore` hat keine Größengrenze, und abgelaufene Einträge werden ohne
gesetztes `evictionInterval` nur beim Zugriff entfernt. Pro Key angelegte Maps (letzte Parameter, Stream-Controller,
Watcher-Zähler) werden nie aufgeräumt. In langlebigen Apps mit wachsendem Key-Raum (Chat-Räume, Detailseiten nach ID)
wächst der Speicher unbegrenzt. Nirgends ist dokumentiert, dass das so beabsichtigt ist oder wie man es begrenzt.
Der Soak-Test mit festem Key-Raum (10.000 Keys) blieb stabil (LIFE-05).
**Nachweis:** Code-Review (Orte oben); `docs/audit/raw/soak.txt`
**Empfehlung:** Optionale Größengrenze mit LRU-Eviction im `CacheStore`, Aufräumen der Per-Key-Strukturen, wenn ein Key
keine Watcher mehr hat; Verhalten und Defaults dokumentieren.
