# Audit Findings

Format nach Spec 6.2. Sortiert nach Schwere (P0 → P3), innerhalb einer Stufe nach ID.
Regel für die Einstufung: Ein Finding, das ein Must-Kriterium blockiert, ist mindestens P1, denn ohne seine
Behebung kann das Gate (Spec 2.5) nicht bestehen.
Maschinenlesbarer Status: `docs/audit/criteria.yaml` (Liste `findings`).

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

### F-014 · P0 · freeze-relevant: nein · Aufwand: M
**Kriterium:** ASYNC-02
**Ort:** `packages/trooper/lib/src/core/trooper.dart:172` (`invalidate`), `packages/trooper/lib/src/core/accessor.dart:58`,
`packages/trooper/lib/src/core/keyed_trooper.dart:181-212,286-290` (`invalidateKey`, `invalidate`, `clearAll`),
`packages/trooper/lib/src/controller/trooper_controller.dart:651` (`clearAll`)
**Befund:** Laut Dartdoc „removes storage“ entfernt `invalidate()` auch den L2-Eintrag. Tatsächlich bleibt er erhalten
und wird beim nächsten `get` wiederhergestellt, bei nicht-keyed **und** bei keyed Troopers.
`TrooperController.clearAll()` löscht persistierte Daten ebenfalls nicht. `KeyedTrooper.clearAll` leert
`_lastParams` synchron, bevor `controller.invalidate()` läuft; `invalidate`/`invalidateKey` löschen nur Keys,
deren Parameter im Speicher bekannt sind. Einträge aus früheren App-Sitzungen werden deshalb nie gelöscht.
Ein Logout per `clearAll()` hinterlässt so Nutzerdaten auf der Platte (im Test: E-Mail-Adressen), und der nächste
Nutzer bekommt sie aus L2 angezeigt. Das ist Default-Verhalten, bricht ein dokumentiertes Versprechen und legt
personenbezogene Daten offen, deshalb P0 (Spec 2.3: Sicherheitslücke, Datenschutz). Zusätzlich bricht
`invalidate()` laufende Requests mit `TrooperCancelledException` ab, was nirgends dokumentiert ist.
**Nachweis:** `async_audit_test.dart` – „invalidate removes L2 storage as documented“, „controller.clearAll removes
persisted QueryTrooper data“, „controller.clearAll removes persisted KeyedQueryTrooper data“, „keyed invalidate purges
L2 entries from an earlier session“ (alle rot)
**Empfehlung:** `invalidate()` und `clearAll()` löschen alle Storage-Keys ihres Namespace, auch solche aus früheren
Sitzungen. Das braucht eine Aufzählung der Keys pro Namespace im `StorageBackend` (siehe F-038). Alternativ die Doku
korrigieren und eine explizite `purge()`-API ergänzen. Das Abbruchverhalten dokumentieren.

### F-017 · P0 · freeze-relevant: nein · Aufwand: S
**Kriterium:** LIFE-02
**Ort:** `packages/trooper/lib/src/core/keyed_stream_trooper.dart:718`
**Befund:** `KeyedStreamTrooper.dispose()` iteriert über `_subscriptions.values` und wartet dabei mit `await sub.cancel()`.
Verändert ein Callback die Map während dieses `await`, bricht `dispose()` mit `ConcurrentModificationError` ab. Die
restlichen Subscriptions werden dann nicht gekündigt, und `super.dispose()` (Stream-Controller, Queue, Cache) läuft
nicht: ein Ressourcenleck, deshalb P0 (Spec 2.3). Der Fehler tritt auch mit Echtzeit auf, ein typischer Auslöser ist
ein Listener, der beim ersten `DataLoaded` `dispose()` aufruft. (Die erste Einschätzung, er sei nur unter `fakeAsync`
reproduzierbar, hat das unabhängige Review widerlegt.)
**Nachweis:** `lifecycle_audit_test.dart` – „LIFE-02 KeyedStreamTrooper dispose from a listener (real time)“ und
„LIFE-02 KeyedStreamTrooper leaves no timers after dispose“ (beide rot, Stacktrace `keyed_stream_trooper.dart 718:38`)
**Empfehlung:** Vor der Schleife eine Kopie ziehen (`List.of(_subscriptions.values)`), Map sofort leeren, dann kündigen.

### F-060 · P0 · freeze-relevant: ja · Aufwand: M
**Kriterium:** FEAT-05
**Ort:** `packages/trooper/lib/src/key/query_key.dart:79-84` (`storageKey`)
**Befund:** Der L2-Schlüssel entsteht aus `'$parameter'`, also aus `toString()`. Enthält ein Record-Parameter eine
Klasse ohne eigenes `toString`, ergibt jeder Wert denselben Schlüssel (`…:(f: Instance of 'Filter')`). Nach einem
Kaltstart liefert `get((f: Filter('A')))` dann die gespeicherten Daten von `Filter('B')`. Im L1-Cache passiert das
nicht, weil `QueryKey` dort mit `==` verglichen wird. Außerdem stehen Parameter im Klartext im Schlüssel; ein
verschlüsselnder Codec (Hook aus F-026) schützt sie nicht. Eine Korrektur ändert das persistierte Format oder braucht
eine API für eigene Schlüssel, ist also freeze-relevant. Gefunden hat das das unabhängige Review.
**Nachweis:** `packages/trooper/test/audit/feature_audit_test.dart` – „L2 keys of different parameters do not collide“ (rot)
**Empfehlung:** Schlüssel aus einer stabilen, kanonischen Serialisierung der Parameter bilden (oder einen
`keyBuilder` verlangen, wenn Parameter nicht serialisierbar sind), optional gehasht; Format versionieren (vgl. F-024).

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

### F-004 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** TEST-03
**Ort:** `packages/trooper/test/core/stream_trooper_test.dart` (16 Stellen), `core/keyed_stream_trooper_test.dart` (12),
`edge_cases/swr_sequence_test.dart` (10), `stream/keyed_stateful_stream_test.dart` (8) u. a.
**Befund:** Beide Suiten liefen 100-mal mit zufälliger Reihenfolge ohne Fehler. Die Tests steuern Zeit aber an 121
Stellen mit echtem `Future.delayed`; `fake_async` ist als Dev-Dependency eingetragen, wird jedoch in keiner Testdatei
verwendet. Die Tests hängen damit von realen Laufzeiten ab (z. B. 50 ms vs. 10 ms in `out_of_order_test.dart`) und
können auf langsamen CI-Runnern kippen; zudem verlängern sie die Laufzeit.
**Nachweis:** `docs/audit/raw/flake_trooper.txt`, `docs/audit/raw/flake_trooper_bloc.txt`, `docs/audit/raw/real_delays.txt`
**Empfehlung:** Zeitabhängige Tests auf `fakeAsync` oder `Completer` umstellen.

### F-005 · P1 · freeze-relevant: nein · Aufwand: S
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

### F-006 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ARCH-02
**Ort:** `packages/trooper/lib/src/telemetry/telemetry_hub.dart`, `packages/trooper/lib/src/telemetry/trooper_logger.dart`
**Befund:** Der Import-Graph von `trooper` ist nicht azyklisch: `telemetry_hub.dart` und `trooper_logger.dart`
importieren sich gegenseitig. Alle übrigen 40 Dateien sind zyklenfrei, `trooper_bloc` ebenfalls. Eine Schichtregel
(welches Modul darf welches importieren) ist nirgends definiert oder automatisiert geprüft.
**Nachweis:** `docs/audit/raw/lakos_trooper.json` (`isAcyclic: false`, `firstCycle`), `tool/audit/scripts/api_arch.sh`
**Empfehlung:** Zyklus auflösen (Logger hängt vom Hub ab, nicht umgekehrt), Schichtregel dokumentieren und
`lakos --no-cycles-allowed` in die CI aufnehmen.

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

### F-011 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** PERF-02
**Ort:** `packages/trooper/benchmark/trooper_benchmark.dart`
**Befund:** Eine Baseline liegt jetzt vor (Median aus drei Läufen, `bench_baseline.txt`), aber die Läufe streuen stark:
Im zweiten Lauf lagen alle vier Benchmarks 20–70 % unter den anderen beiden (z. B. Request-Coalescing 45.983 statt
~131.000 ops/s). Mit dieser Streuung ist eine 10-%-Regressionsschranke nicht belastbar. Eine CI-Prüfung fehlt ganz.
**Nachweis:** `docs/audit/raw/bench_run1.txt` … `bench_run3.txt`, `docs/audit/raw/bench_baseline.txt`
**Empfehlung:** Warm-up und mehrere Messwiederholungen pro Benchmark (z. B. `benchmark_harness`), Median und Streuung
ausgeben; Regressionsprüfung erst auf dieser Basis in die CI aufnehmen.

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

### F-020 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ERR-02
**Ort:** `packages/trooper/lib/src/core/trooper.dart:119-121` (`runSideEffect`), `core/keyed_trooper.dart:116-118`,
`core/trooper_mutation.dart:125,155,175`, `concurrency/cancel_token.dart:48,71`, `controller/trooper_controller.dart:646`
**Befund:** Fehler in Nutzer-Callbacks verschwinden spurlos: Side-Effects (`onData`, `onError`, `onRequestStarted`,
`onStarted`, `onSuccess` …), Cancel-Listener und `invalidate()` registrierter Ziele werden in `catch (_) {}` gekapselt;
asynchrone Side-Effects werden per `.ignore()` verworfen. Weder Zone noch Telemetrie erfahren davon. Ein Bug in einem
`onSuccess`-Handler (z. B. Navigation nach dem Speichern) bleibt damit unsichtbar.
**Nachweis:** `packages/trooper/test/audit/error_audit_test.dart` – „ERR-02 failing side effect is not swallowed silently“ (rot);
`docs/audit/raw/catch_sites.md`
**Empfehlung:** Callback-Fehler mindestens als Telemetrie-Event melden (z. B. `SideEffectErrorEvent`) und in der Zone
melden (`Zone.current.handleUncaughtError`), statt sie zu verwerfen.

### F-021 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** ERR-02
**Ort:** L2-Lesepfade `core/query_trooper.dart:212`, `local_trooper.dart:293`, `keyed_local_trooper.dart:376`,
`keyed_query_trooper.dart:223`, `stream_trooper.dart:235,484`, `keyed_stream_trooper.dart:230,497`;
Schreiben `stream_trooper.dart:324,554-555`, `keyed_stream_trooper.dart:316,612-613`; 33 × `storage.delete(...).ignore()`
**Befund:** Persistenzfehler werden uneinheitlich behandelt. `QueryTrooper` meldet Schreibfehler als
`PersistenceErrorEvent`; Lese- und Decode-Fehler beim Wiederherstellen aus L2 werden dagegen in allen Troopers still
behandelt (Eintrag löschen, weiter mit Fetch), ohne Event. `StreamTrooper` und `KeyedStreamTrooper` verwerfen auch
Schreibfehler (`.ignore()`, `catch (_)` mit Kommentar „Non-critical“). Fehlgeschlagene `delete`-Aufrufe werden nirgends
gemeldet; ein nicht gelöschter Eintrag bleibt dann unbemerkt im Speicher (vgl. F-014).
**Nachweis:** `error_audit_test.dart` – „ERR-02 corrupt L2 entry is reported via telemetry“ (rot); `docs/audit/raw/catch_sites.md`
**Empfehlung:** Eine zentrale Persistenz-Hilfsfunktion für Lesen/Schreiben/Löschen, die jeden Fehler als
`PersistenceErrorEvent` meldet; von allen Troopers nutzen lassen (beseitigt nebenbei die Duplikation aus F-008).

### F-022 · P1 · freeze-relevant: ja · Aufwand: S
**Kriterium:** ERR-01
**Ort:** `packages/trooper/lib/src/error/trooper_exception.dart`
**Befund:** `TrooperException` ist `sealed` und kennt `TrooperCancelledException`, `TrooperTimeoutException` und
`TrooperStorageException`. Codec-Fehler haben keinen eigenen Typ; sie erscheinen roh (z. B. `FormatException`) in
`PersistenceErrorEvent` und sind dort nicht von Storage-Fehlern zu unterscheiden. Fetch-Fehler werden unverändert
durchgereicht, das ist vertretbar. Weil die Klasse `sealed` ist, bricht jeder nach 1.0 ergänzte Subtyp exhaustive
`switch`-Ausdrücke der Nutzer, ist also ein Breaking Change.
**Nachweis:** Code-Review `trooper_exception.dart`; `error_audit_test.dart` ERR-04-Fälle „wrong payload type“
**Empfehlung:** Vor dem Freeze `TrooperCodecException` ergänzen und entscheiden, ob die Hierarchie `sealed` bleiben soll
(Erweiterbarkeit) oder bewusst geschlossen ist.

### F-023 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ERR-03
**Ort:** `packages/trooper/lib/src/config/retry_policy.dart` (`delayForAttempt`)
**Befund:** Backoff, Obergrenze und `retryWhen` arbeiten exakt wie konfiguriert (Aufrufe bei 0/100/300/700 ms bzw.
0/100/300/550 ms mit `maxDelay`). Jitter fehlt: Alle Clients wiederholen nach einem Serverausfall im selben Takt
(Thundering Herd).
**Nachweis:** `error_audit_test.dart` – ERR-03-Gruppe (3 grün, „backoff applies jitter“ rot)
**Empfehlung:** Optionalen Jitter (z. B. „full jitter“) ergänzen, per Parameter abschaltbar für deterministische Tests.

### F-024 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** ERR-04
**Ort:** `packages/trooper/lib/src/storage/storage_envelope.dart:59-61` und alle L2-Lesepfade (z. B. `query_trooper.dart:140-147`)
**Befund:** Die Envelope-Version wird geschrieben, aber nie geprüft. Ein Eintrag ohne `version` wird als `currentVersion`
gelesen, ein Eintrag mit `version: 999` aus einer neueren App-Version ebenso; beide werden ungeprüft dekodiert und
ausgeliefert. Ein Migrationspfad existiert nicht. Nach 1.0 persistieren Apps Daten in diesem Format; jede Änderung am
Format oder am Codec braucht dann eine Migration. Korrupte JSON-Daten und falsche Payload-Typen fallen korrekt auf den
Fetch zurück (aber still, siehe F-021). Die Hypothese ERR-04 aus Spec §5 ist bestätigt.
**Nachweis:** `error_audit_test.dart` – „ERR-04/SEC-03 … missing version“ und „… future version“ (rot), „not json“ und
„wrong payload type“ (grün)
**Empfehlung:** Unbekannte und fehlende Versionen verwerfen, einen Migrations-Hook pro Codec/Trooper vorsehen und
das Format in der Doku als stabil beschreiben.

### F-026 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** SEC-01
**Ort:** `packages/trooper/lib/src/storage/storage_backend.dart`, `codec/trooper_codec.dart`, READMEs, `skills/*/SKILL.md`
**Befund:** L2 speichert Payloads als Klartext-JSON. Ein Verschlüsselungs-Hook ist strukturell möglich (eigenes
`StorageBackend` oder eigener `TrooperCodec` als Wrapper), aber nirgends dokumentiert; README, Dartdoc und Skills
erwähnen weder Klartext-Persistenz noch den Umgang mit sensiblen Daten.
**Nachweis:** Code-Review; `grep` nach „encrypt|plaintext|sensitive“ ohne Treffer
**Empfehlung:** Abschnitt „Sensible Daten“ mit Beispiel eines verschlüsselnden Backends (z. B. über
`flutter_secure_storage`) ergänzen.

### F-027 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** SEC-02
**Ort:** `packages/trooper/lib/src/telemetry/trooper_logger.dart` (`ConsoleTrooperLogger.log`),
`key/query_key.dart:87` (`describe`), `telemetry/trooper_event.dart` (`toString` von `RequestErrorEvent` u. a.)
**Befund:** Der Logger ist opt-in (`attach()`) und gibt keine Antwort-Payloads aus. Er gibt aber jeden Query-Parameter
im Klartext aus (`QueryKey.describe()`) sowie `error.toString()`. Parameter enthalten in der Praxis häufig
personenbezogene Daten (im Test: eine E-Mail-Adresse), die so in Konsolen- und Crash-Logs landen.
**Nachweis:** `error_audit_test.dart` – „SEC-02 … logger does not print query parameters“ (rot), „… response payloads“ (grün)
**Empfehlung:** Parameter standardmäßig maskieren oder nur ihren Hash loggen; Ausgabe per Option aktivierbar machen.

### F-028 · P1 · freeze-relevant: ja · Aufwand: M
**Kriterium:** API-01
**Ort:** `packages/trooper/lib/trooper.dart`, `packages/trooper_bloc/lib/trooper_bloc.dart`; Einzelentscheidungen in `docs/audit/api-inventory.md`
**Befund:** Von 88 exportierten Symbolen (81 Typen, 7 Aliase) sind sechs Implementierungsdetails:
`StatefulStreamController` und `KeyedStatefulStream` (als Konstruktorparameter injizierbar, damit kann fremder Code in
den State eines Troopers emittieren), `KeyedTrooperAccessor`, `WatchedHandle`, `WatchedUpdateCallback` und
`TlocSourceUpdateEvent`. Dazu kommen der Doppelname `ConflictPolicy` (`query_conflict_policy.dart:111`) und der
Re-Export von `FutureOr`. Alles, was mit 1.0 exportiert ist, lässt sich danach nur per Major-Release entfernen.
**Nachweis:** `docs/audit/api-inventory.md`, `docs/audit/raw/api_trooper.json`, `api_trooper_bloc.json`
**Empfehlung:** Die Einträge mit „intern machen“ und „entfernen“ vor dem Freeze umsetzen.

### F-029 · P1 · freeze-relevant: ja · Aufwand: S
**Kriterium:** API-02
**Ort:** 38 Klassen laut `docs/audit/raw/class_modifiers.txt`, u. a. `QueryTrooper`, `KeyedQueryTrooper`, `TrooperController`,
`TrooperConfig`, `CacheStore`, `RetryPolicy`, `Tloc`, `Tubit`
**Befund:** 38 öffentliche Klassen tragen keinen der Modifier `final`, `base`, `interface` oder `sealed`. Nutzer
können sie damit nicht nur erweitern, sondern auch `implements`-en; jede nach 1.0 ergänzte Methode bricht dann
Fremd-Implementierungen. Die Hypothese aus Spec §5 ist bestätigt (korrigierte Zahl: 38 statt 46, die Vorab-Zählung
enthielt private und `abstract`-Deklarationen).
**Nachweis:** `docs/audit/raw/class_modifiers.txt` (`tool/audit/bin/class_modifiers.dart`)
**Empfehlung:** Modifier-Vorschläge aus `api-inventory.md` übernehmen: konkrete Troopers, Konfigurations- und
Infrastrukturklassen `final`; zur Erweiterung gedachte Basisklassen (`Trooper`, `TrooperController`, `Tloc`, `Tubit`,
`TrooperCodec`) `abstract base`.

### F-030 · P1 · freeze-relevant: ja · Aufwand: M
**Kriterium:** API-03
**Ort:** `controller/trooper_controller.dart:667` (`executeOrder66`), `:156`/`:672` (`onInit`/`initialize` und weitere Paare),
`:258,315,440,588` (Fabriken), `config/trooper_config.dart:63,74,78`, `core/trooper.dart:54`, Keyed-Troopers
**Befund:** Die API hat Redundanzen und Stolperstellen, die mit dem Freeze dauerhaft würden:
(1) `executeOrder66()` ist ein Alias für `clearAll()` ohne fachliche Bedeutung.
(2) Lifecycle-Hooks gibt es doppelt (`onInit`/`initialize`, `onPause`/`pause`, `onResume`/`resume`, `onRecover`/`recover`, `onDispose`/`dispose`).
(3) `TrooperConfig.queryConflictPolicy` dupliziert `conflictPolicy`.
(4) `TrooperConfig.defaultConfig` ist ein global veränderliches statisches Feld, mit zwei Settern (`TrooperConfig.setDefaultConfig`, `Trooper.setDefaultConfig`).
(5) Die Controller-Fabriken haben zwei sich ausschließende optionale Parameter `fetch`/`cancellableFetch`, nur per `assert` geprüft.
(6) Keys lassen sich auf vier Wegen adressieren (`trooper['k']`, `key()`, `getKey`/`watchKey`, `currentKey`).
(7) `getMany` gibt es nur an `KeyedQueryTrooper`.
**Nachweis:** `docs/audit/api-inventory.md`, Abschnitt „Weitere Punkte“; Paarvergleich auf Basis von `api_trooper.json`
**Empfehlung:** Aliase und doppelte Namen streichen, globale Defaults nur über den Controller setzen, Fabriken in zwei
benannte Varianten trennen (`query`/`cancellableQuery`) und einen Weg zur Key-Adressierung festlegen.

### F-031 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** API-04
**Ort:** Repository (keine Policy-Datei), `packages/*/lib` (0 × `@Deprecated`)
**Befund:** Es gibt keine Deprecation-Policy. Für ein 1.0-Release mit eingefrorener API ist eine Regel nötig, wie lange
veraltete APIs erhalten bleiben und wie Migrationshinweise aussehen.
**Nachweis:** `grep -rn "@Deprecated"` ohne Treffer; keine Policy in README, CONTRIBUTING oder `docs/`
**Empfehlung:** Policy dokumentieren (mindestens ein Minor-Release mit `@Deprecated('Use X; removed in 2.0')` vor dem
Entfernen) und im README verlinken.

### F-032 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** API-05
**Ort:** Repository (keine CI), `docs/audit/raw/api_trooper.json`, `api_trooper_bloc.json`
**Befund:** Es gibt weder eine eingefrorene API-Baseline noch einen automatisierten API-Diff. Breaking Changes würden
nach 1.0 unbemerkt in Minor-Releases landen. Die Extrakte aus diesem Audit eignen sich als erste Baseline, sobald die
API-Findings umgesetzt sind.
**Nachweis:** fehlendes `.github/`; `dart_apitool extract` läuft fehlerfrei (`docs/audit/raw/api_*.txt`)
**Empfehlung:** Nach Umsetzung von F-028–F-030 die Baseline einfrieren und `dart_apitool diff` in der CI gegen das
letzte Release laufen lassen.

### F-033 · P1 · freeze-relevant: ja · Aufwand: S
**Kriterium:** API-06
**Ort:** `packages/trooper_bloc/lib/trooper_bloc.dart:4-6`, `packages/trooper_bloc/pubspec.yaml` (`trooper: ^0.1.0-beta.1`)
**Befund:** `trooper_bloc` re-exportiert `trooper` vollständig, dazu `Emitter` aus `flutter_bloc` und `FutureOr` aus
`dart:async`. Damit ist die öffentliche API von `trooper_bloc` die Summe dreier APIs, deren Versionen getrennt laufen.
Eine Regel, wie sich Versionen beider Packages zueinander verhalten, ist nicht dokumentiert. Die Hypothese aus Spec §5
ist bestätigt.
**Nachweis:** Code-Review; `docs/audit/api-inventory.md`, Abschnitt „Re-Exporte“
**Empfehlung:** Entscheiden: entweder Re-Export behalten und `trooper_bloc` im Lockstep mit `trooper` versionieren,
oder nur die BLoC-Symbole exportieren. `Emitter` und `FutureOr` nicht re-exportieren.

### F-034 · P1 · freeze-relevant: ja · Aufwand: S
**Kriterium:** API-07
**Ort:** `packages/trooper/lib/src/state/stateful_data.dart:190` (`base class DataLoaded`),
`packages/trooper_bloc/lib/src/sources/watched.dart` (`WatchedHandle`-Konstruktor)
**Befund:** Die Zustandsklassen sind immutable und implementieren `==`/`hashCode`. `DataLoaded` ist aber `base` statt
`final`: Fremder Code darf `DataLoaded` damit erweitern, obwohl `DataRefreshing` (dieselbe Bibliothek) die einzige
gewollte Subklasse ist. `dynamic` kommt nur in den JSON-Hilfen (vertretbar) und im Callback von `WatchedHandle` vor.
**Nachweis:** `docs/audit/api-inventory.md`; `docs/audit/raw/api_*.json`
**Empfehlung:** `DataLoaded` auf `final` setzen; `WatchedHandle` intern machen (F-028).

### F-035 · P1 · freeze-relevant: ja · Aufwand: S
**Kriterium:** OBS-01
**Ort:** `packages/trooper/lib/src/telemetry/trooper_event.dart:5` (`sealed class TrooperEvent`) und alle Event-Klassen
**Befund:** Acht Telemetrie-Events gehören zur Public API. 23 ihrer Member sind undokumentiert (siehe F-002). Weil
`TrooperEvent` `sealed` ist, bricht jedes neue Event nach 1.0 exhaustive `switch`-Ausdrücke der Nutzer. Neue Events
sind aber absehbar (z. B. für F-020 und F-021).
**Nachweis:** Code-Review; `docs/audit/raw/analyze_vga.txt` (`public_member_api_docs` in `trooper_event.dart`)
**Empfehlung:** `TrooperEvent` öffnen (abstract base mit `final`-Subklassen) oder neue Events vor dem Freeze ergänzen
und den Katalog als stabil dokumentieren.

### F-038 · P1 · freeze-relevant: ja · Aufwand: M
**Kriterium:** ARCH-05
**Ort:** `packages/trooper/lib/src/storage/storage_backend.dart:3-34`, `codec/trooper_codec.dart`, `telemetry/trooper_logger.dart`
**Befund:** Der Vertrag der Erweiterungspunkte ist dünn. Bei `StorageBackend` sagt die Dartdoc pro Methode nur einen
Satz: Es bleibt offen, ob Methoden werfen dürfen, was `delete` zurückgibt (`String?`, vermutlich den alten Wert), ob
Aufrufe parallel erfolgen und ob `clear()` das ganze Backend leert (gefährlich, wenn es mit App-Daten geteilt wird).
`getAllKeys`, `containsKey` und `clear` werden von der Bibliothek nie aufgerufen, Implementierer müssen sie trotzdem
liefern. Ein exportiertes Contract-Test-Kit fehlt; `MockStorageBackend` liegt nur in `test/fixtures/`. Das Interface ist
`abstract interface`: Jede ergänzte Methode bricht nach 1.0 alle Fremd-Implementierungen.
**Nachweis:** Code-Review; `grep` nach Aufrufen von `getAllKeys`/`containsKey`/`clear` in `lib/` ohne Treffer
**Empfehlung:** Den Vertrag vor dem Freeze bewusst festlegen: Für den Fix von F-014 (Löschen aller Keys eines
Namespace, auch aus früheren Sitzungen) braucht die Bibliothek eine Aufzählung oder ein präfixbasiertes Löschen
(z. B. `getAllKeys` beibehalten oder durch `deleteWhere(prefix)` ersetzen); ungenutzte Methoden wie `containsKey` und ein
backendweites `clear()` entfallen. Fehler- und Nebenläufigkeitsvertrag dokumentieren und eine Contract-Test-Suite
(z. B. `package:trooper/testing.dart`) exportieren.

### F-039 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** TEST-04
**Ort:** `packages/trooper/lib/src/storage/cache_entry.dart:56` u. a. (24 × `DateTime.now()` in `lib/src`)
**Befund:** `FakeAccessor` in `trooper_bloc/testing.dart` ist vollständig getestet (46/46 Zeilen, 21/21 Branches) und
dokumentiert. Für Nutzer ohne BLoC gibt es keine Test-Helfer. Vor allem ist die Zeit nicht injizierbar: TTL, Stale-
Erkennung und Envelope-Ablauf lesen `DateTime.now()` direkt, deshalb kann `fakeAsync` den Cache nicht altern lassen.
Nutzer können Ablauf- und SWR-Verhalten ihrer App nicht deterministisch testen. Auch dieses Audit musste abgelaufene
Einträge über `putEntry` mit Vergangenheitsdatum anlegen.
**Nachweis:** `grep -rn "DateTime.now()" packages/trooper/lib/src` (24 Treffer); `coverage_bloc/lcov.info`
**Empfehlung:** `package:clock` (wird von `fake_async` gesteuert) oder eine injizierbare Zeitquelle nutzen; einfache
Test-Helfer für den Core exportieren.

### F-041 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** PERF-01
**Ort:** `packages/trooper/benchmark/trooper_benchmark.dart:51` (`benchmarkL1CacheHit`)
**Befund:** Die Benchmarks decken Coalescing, Stream-Dispatch und Speicher für 10.000 Keys ab. SWR und die Ableitung
in `trooper_bloc` fehlen. „L1 Cache-Hit“ misst den rohen `CacheStore` (34 ns), nicht den Pfad, den Nutzer aufrufen:
Ein Cache-Hit über `QueryTrooper.get` kostet etwa 800 ns (`telemetry_overhead.txt`); die Benchmark-Tabelle
suggeriert damit einen 20-fach schnelleren Pfad, als Nutzer tatsächlich bekommen.
**Nachweis:** `docs/audit/raw/bench_baseline.txt`, `docs/audit/raw/telemetry_overhead.txt`
**Empfehlung:** Benchmarks für `QueryTrooper.get` (Hit, SWR), `KeyedQueryTrooper` und `Tubit`-Ableitung ergänzen.

### F-043 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** FEAT-07 (auch DOC-06)
**Ort:** `README.md:100-104` (Quickstart), `packages/trooper/README.md:291,330`, `packages/trooper_bloc/README.md:68,147,186,211`,
`packages/trooper/skills/trooper-reactive-data-flow/SKILL.md:146,223`, `packages/trooper_bloc/skills/trooper-bloc-state-management/SKILL.md:291,510`,
`packages/trooper/example/README.md:98`
**Befund:** Von 44 Dart-Snippets in READMEs und Skills nutzen mehrere eine API, die es so nicht gibt (Fehler, die nur
fehlende Beispiel-Klassen betreffen, nicht mitgezählt):
- Der Quickstart im Root-README ruft `super('ArticleController')` auf, `TrooperController` hat keinen solchen Parameter.
- `RetryPolicy.exponential(multiplier: …)` statt `backoffMultiplier`.
- `TelemetryHub.global.addListener(...)` existiert nicht.
- Alle `Tloc`/`Tubit`-Beispiele lassen die seit Commit `ddff790` verpflichtenden `onAnyLoading`/`onAnyError` weg.
- Der BLoC-Skill zeigt `QueryTrooper(fetcher: …, cacheDuration: …)` statt `fetch:`/`config:`.
- Parameterlose Aufrufe wie `accessor.get()`, `counter.set(10)` kompilieren nicht (siehe F-044).

Wer der Doku oder den Agent-Skills folgt, bekommt Compilerfehler.
**Nachweis:** `docs/audit/raw/snippets_analyze.txt` mit Zuordnung in `snippets_index.tsv` (`tool/audit/scripts/snippets.py`)
**Empfehlung:** Snippets korrigieren und in der CI extrahieren und analysieren (z. B. mit diesem Skript oder `code_excerpter`).

### F-044 · P1 · freeze-relevant: ja · Aufwand: M
**Kriterium:** API-03
**Ort:** alle neun `Parameterless*`-Extensions, u. a. `core/accessor.dart` (`ParameterlessAccessor`), `core/local_trooper.dart`,
`core/keyed_*_trooper.dart`, `core/trooper_mutation.dart`, `core/keyed_accessor.dart`
**Befund:** Die Extensions sollen Kurzformen für Troopers ohne Parameter (`()`) anbieten, z. B. `accessor.get()` oder
`mutation()`. In Dart verdecken Instanzmethoden aber jede gleichnamige Extension-Methode, und alle 51 Extension-Member
heißen genau wie Instanzmethoden des erweiterten Typs (`get`, `refresh`, `watch`, `set`, `getKey`, `call` …). Kein
einziges ist über die normale Aufrufsyntax erreichbar; `q.get()` liefert „1 positional argument expected“. Die eigenen
Tests des Packages umgehen das mit expliziter Extension-Syntax (`ParameterlessKeyedQueryTrooper(query).getKey(10)` in
`keyed_query_trooper_test.dart:269`). README und Skills werben trotzdem mit der Kurzform. Neun öffentliche Extensions
mit 51 Membern wären mit dem Freeze eingefroren, obwohl niemand sie normal aufrufen kann.
**Nachweis:** `docs/audit/raw/parameterless_shadowing.txt`; Analyzer-Fehler in `snippets_analyze.txt` (`SKILL.md:146,223`, `trooper_bloc/README.md:68`)
**Empfehlung:** Vor dem Freeze die Parameter der Instanzmethoden für `P = ()` optional machen (z. B. über einen
`P? parameter` mit `()`-Default in den Parameterless-Fällen) oder die Extensions entfernen; Doku angleichen.

### F-045 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** DOC-02
**Ort:** `README.md:5,8` (Badges), `README.md:57,66,68,308-316` (11 `file:///`-Links), `README.md:275` (GIF), `packages/trooper/README.md:24` (Anker), `:376`
**Befund:** Die READMEs enthalten falsche oder tote Angaben: Das Badge „Dart 3.5+“ widerspricht `sdk: ^3.12.0`; das
Badge „very good analysis“ widerspricht `analysis_options.yaml` (F-001); 11 Links zeigen auf `file:///Users/hannes/...`;
das Architektur-GIF im Root-README verweist auf `doc/trooper_architecture_flow.gif`, das im Root nicht existiert
(es liegt unter `packages/trooper/doc/` bzw. `docs/animation/`); der Inhaltsverzeichnis-Anker
`#architecture-at-a-glance` passt nicht zur Überschrift „Architecture at a Glance (visualized by AI 🙃)“; der Abschnitt
„Ecosystem“ nennt ein Paket `trooper_flutter`, das es nicht gibt; „Telemetry & DevTools“ verspricht eine
DevTools-Integration, die fehlt. Die pub.dev-Links liefern bis zum Release 404. Die Hypothese DOC-02 aus Spec §5 ist
bestätigt.
**Nachweis:** `docs/audit/raw/linkcheck.txt`, Link- und Anker-Prüfung (Task 12), `docs/audit/traceability.md` (C-010, C-019, C-028, C-029)
**Empfehlung:** Angaben korrigieren, Links relativ oder als GitHub-URL setzen, Linkcheck in die CI aufnehmen.

### F-046 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** FEAT-01
**Ort:** `docs/audit/traceability.md`
**Befund:** Von 30 Feature-Claims sind 16 belegt, 4 nur teilweise und 10 widerlegt. Die widerlegten Claims sind
jeweils eigene Findings: Sequence-ID bei `parallel` (F-012), L2-Löschung durch `invalidate` (F-014), kooperativer
Abbruch für Queries und Mutationen (F-015), parameterlose Kurzformen (F-044), nicht existierende APIs und Pakete
(F-043, F-045). Zwei belegte Claims (Microtask-Batching, `DataRefreshing` im BLoC) prüft nur der Audit-Prüftest,
die Suite des Packages nicht.
**Nachweis:** `docs/audit/traceability.md`
**Empfehlung:** Widerlegte Claims korrigieren oder implementieren; die Audit-Prüftests für C-005 und C-024 in die
reguläre Suite übernehmen.

### F-047 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** DOC-03
**Ort:** `packages/trooper/README.md`, `packages/trooper_bloc/README.md`
**Befund:** Quickstart und Zustandsmodell sind gut erklärt; Rezepte gibt es für Pagination und Retry. Eine FAQ fehlt,
ebenso Rezepte für häufige Aufgaben wie Logout/Reset, Optimistic Updates, Offline-Betrieb oder Tests ohne BLoC.
**Nachweis:** Review der READMEs (Überschriften-Inventar)
**Empfehlung:** FAQ und Rezeptsammlung ergänzen, insbesondere „Nutzerdaten beim Logout löschen“ (vgl. F-014).

### F-048 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** DOC-04
**Ort:** Doku insgesamt
**Befund:** Es gibt keinen Abschnitt, der die Laufzeitgarantien verbindlich beschreibt: Reihenfolge und Konflikte
(was passiert bei überlappenden Requests je Policy), Verhalten von `invalidate`/`refresh` während laufender Requests
(sie brechen ab, siehe F-014), Verhalten nach `dispose` (F-016), Fehlerkanäle (State vs. Telemetrie vs. Exception)
und Isolate-Grenzen. Für ein 1.0 mit eingefrorener API ist das der eigentliche Vertrag; mehrere Findings dieses Audits
sind Abweichungen von impliziten, nirgends festgeschriebenen Erwartungen.
**Nachweis:** Review von README, Dartdoc und Skills
**Empfehlung:** Abschnitt „Guarantees“ schreiben und jede Garantie mit einem Test verknüpfen (die Audit-Prüftests sind
ein Ausgangspunkt).

### F-050 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** COMPAT-03
**Ort:** `packages/trooper_bloc/pubspec.yaml:17-18`
**Befund:** `trooper_bloc` verlangt `sdk: ^3.12.0`, aber `flutter: ">=3.24.0"`. Flutter 3.24 bringt Dart 3.5 mit;
die Flutter-Untergrenze ist damit wirkungslos und täuscht Kompatibilität mit älteren Flutter-Versionen vor. Das
Root-README wiederholt „Flutter ≥ 3.24“ als Badge. Die Hypothese COMPAT-03 aus Spec §5 ist bestätigt.
**Nachweis:** Review `pubspec.yaml`; `docs/audit/raw/linkcheck.txt` (Badge)
**Empfehlung:** Flutter-Untergrenze auf die erste Flutter-Version mit Dart 3.12 anheben und Badge angleichen.

### F-052 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** REL-02
**Ort:** `packages/trooper/pubspec.yaml` (`0.1.0-beta.1`), `packages/trooper_bloc/pubspec.yaml` (`0.1.2-beta.1`), `CHANGELOG.md:22` (`[0.1.0]`)
**Befund:** Es gibt keine Versionsstrategie für das Monorepo. Die Versionen laufen bereits auseinander, das
Root-CHANGELOG nennt eine Version 0.1.0, die keines der Pakete trägt. Einen automatisierten Release-Prozess (Tag →
Publish über GitHub OIDC) gibt es nicht; die Release-Reihenfolge (`trooper` vor `trooper_bloc`, F-009) ist nirgends
festgehalten.
**Nachweis:** Review der Manifeste und CHANGELOGs; kein `.github/`
**Empfehlung:** Lockstep- oder unabhängige Versionierung festlegen (bei vollständigem Re-Export Lockstep, siehe F-033)
und einen Publish-Workflow mit OIDC einrichten.

### F-054 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** GOV-01
**Ort:** Repository (kein `.github/workflows/`)
**Befund:** Es gibt keine CI. Keine der Schwellen aus diesem Audit (Analyzer, Format, Tests, Coverage, SDK-Matrix,
Web/WASM, API-Diff, Benchmarks, Linkcheck) wird automatisch geprüft. Deshalb kann keine Dimension Reifegrad 3
erreichen.
**Nachweis:** Repository-Inhalt; `automated_in_ci: false` für alle Kriterien in `docs/audit/criteria.yaml`
**Empfehlung:** Workflow mit den Skripten aus `tool/audit/scripts/` als Ausgangspunkt aufsetzen.

### F-055 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** GOV-02
**Ort:** Repository-Root
**Befund:** `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` sowie Issue- und PR-Templates fehlen; das README hat einen
vierzeiligen Contributing-Abschnitt.
**Nachweis:** `ls -a` im Root; GitHub-API
**Empfehlung:** Die drei Dateien und Templates (Bug, Feature, PR-Checkliste) ergänzen.

### F-056 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** GOV-03
**Ort:** Doku
**Befund:** Es gibt keine Support-Policy: welche Dart- und Flutter-Versionen unterstützt werden, wie lange 1.x
gepflegt wird und wie Sicherheitsfixes zurückportiert werden.
**Nachweis:** Review von README und Repository
**Empfehlung:** Support-Policy im README oder in `SUPPORT.md` festhalten.

### F-058 · P1 · freeze-relevant: nein · Aufwand: S
**Kriterium:** SEC-04
**Ort:** Repository-Root
**Befund:** Der OSV-Scan findet keine bekannten Schwachstellen in den 69 aufgelösten Paketen. Eine `SECURITY.md` mit
Meldeweg für Sicherheitslücken fehlt; der OSV-Scan läuft nicht in der CI.
**Nachweis:** `docs/audit/raw/osv.txt`
**Empfehlung:** `SECURITY.md` anlegen (Kontakt, Antwortzeiten, unterstützte Versionen) und den OSV-Scan in die CI aufnehmen.

### F-059 · P1 · freeze-relevant: nein · Aufwand: L
**Kriterium:** TEST-02
**Ort:** `packages/trooper/lib/src/core/stream_trooper.dart` (46,0 %), `storage/storage_envelope.dart` (50,0 %),
`core/keyed_stream_trooper.dart` (51,4 %), `core/trooper.dart` (54,2 %), `core/local_trooper.dart` (56,7 %),
`storage/storage_backend.dart` (0 von 1)
**Befund:** Über die Module `core`, `concurrency`, `storage` und `controller` überleben 557 von 1.415 Mutanten, der
Mutation-Score liegt bei 60,6 % (Gate: 75 %). Der Lauf war vollständig, ohne Stichprobe; Mutanten auf nicht
abgedeckten Zeilen zählen als überlebend. Gut abgesichert sind `cancel_token.dart` und `cache_entry.dart` (je 100 %),
`cache_store.dart` (86 %), `query_queue.dart` (83,8 %) und `keyed_accessor.dart` (83,3 %). Die schwachen Dateien
decken sich mit den Coverage-Lücken (F-003) und den Fundorten der Lifecycle- und Persistenz-Findings (F-017, F-021,
F-024). Bei `storage_envelope.dart` überleben 7 von 14 Mutanten, genau dort fehlt die Versionsprüfung (F-024).
**Nachweis:** `docs/audit/raw/mutation/summary.txt`, HTML-Reports unter `docs/audit/raw/mutation/<gruppe>/`
(`tool/audit/scripts/mutation.sh`, Konfiguration `tool/audit/mutation/*.xml`)
**Empfehlung:** Überlebende Mutanten der genannten Dateien als Checkliste für fehlende Assertions nutzen, beginnend mit
den Stream-Troopers.

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

### F-018 · P2 · freeze-relevant: nein · Aufwand: S
**Kriterium:** LIFE-02
**Ort:** `packages/trooper/lib/src/concurrency/query_queue.dart:151`
**Befund:** Der Backoff zwischen Retries ist ein nicht abbrechbares `Future.delayed`. Nach `dispose()` bleibt der Timer
bis zum Ablauf der Wartezeit aktiv (im Test: eine Minute) und hält Trooper und Closure so lange am Leben; erst danach
wird das Cancel-Token geprüft.
**Nachweis:** `lifecycle_audit_test.dart` – „LIFE-02 retry backoff timer does not outlive dispose“ (rot)
**Empfehlung:** Backoff über einen `Timer` umsetzen, der beim Abbruch des Cancel-Tokens gecancelt wird.

### F-037 · P2 · freeze-relevant: nein · Aufwand: L
**Kriterium:** ARCH-04
**Ort:** `packages/trooper/lib/src/core/*_trooper.dart`
**Befund:** Die Keyed- und Non-Keyed-Varianten teilen große Teile ihres Codes per Copy-and-Paste: 40 % der relevanten
Zeilen von `query_trooper.dart` stehen nahezu identisch in `keyed_query_trooper.dart`, 39 % von `local_trooper.dart`
in `keyed_local_trooper.dart`, 27 % von `stream_trooper.dart` in `keyed_stream_trooper.dart`. Der Persistenzblock
(Envelope bauen, schreiben, Fehler melden) existiert 12-mal, der L2-Restore-Pfad 8-mal. Mehrere Findings sind Folgen
davon: uneinheitliche Fehlerbehandlung (F-021), Bugs nur in einer Variante (F-017).
**Nachweis:** `docs/audit/raw/duplication.txt` (6-Zeilen-Fenster, normalisiert)
**Empfehlung:** Persistenz (L2 lesen/schreiben/löschen) und Fetch-Orchestrierung in gemeinsame Bausteine auslagern,
die beide Varianten nutzen.

### F-040 · P2 · freeze-relevant: nein · Aufwand: M
**Kriterium:** TEST-05
**Ort:** `packages/trooper/test/`
**Befund:** Es gibt keine Property-Based-Tests für die Invarianten von `CacheStore`, `TrooperQueryQueue` und
`TrooperMutationQueue`. Der randomisierte Prüftest dieses Audits (ASYNC-07, 1.000 Seeds) zeigt, dass sich das
Muster mit `fakeAsync` einfach umsetzen lässt, er deckt aber nur `QueryTrooper` mit Default-Policy ab.
**Nachweis:** Review von `packages/*/test`; `packages/trooper/test/audit/async_audit_test.dart` (ASYNC-07)
**Empfehlung:** Randomisierte Interleaving-Tests auf alle Conflict-Policies und die Keyed-Varianten ausweiten; das
hätte F-012 gefunden.

### F-049 · P2 · freeze-relevant: nein · Aufwand: S
**Kriterium:** DOC-05
**Ort:** `packages/trooper/CHANGELOG.md`, `packages/trooper_bloc/CHANGELOG.md`, `CHANGELOG.md`
**Befund:** Nur das Root-CHANGELOG folgt Keep a Changelog (`## [0.1.0] - 2026-10-08`). Die Paket-CHANGELOGs haben
weder Datum noch die Gliederung Added/Changed/Fixed; `trooper_bloc` nennt die aktuelle Version nicht (F-009). Ein
Migrationsleitfaden von 0.x auf 1.0 fehlt; er wird nach den API-Findings (F-028–F-030, F-044) nötig.
**Nachweis:** Review der drei CHANGELOGs
**Empfehlung:** Paket-CHANGELOGs auf Keep a Changelog umstellen, Migrationsleitfaden mit dem 1.0-Release schreiben.

### F-057 · P2 · freeze-relevant: nein · Aufwand: S
**Kriterium:** GOV-04
**Ort:** GitHub-Repository `ParceApp/trooper` (öffentlich)
**Befund:** `main` ist nicht geschützt; Dependabot-Security-Updates und Secret Scanning sind deaktiviert; eine
Dependabot-Konfiguration für pub-Abhängigkeiten fehlt.
**Nachweis:** `gh api repos/ParceApp/trooper/branches/main/protection` (404), `gh api repos/ParceApp/trooper` (`security_and_analysis`)
**Empfehlung:** Branch-Protection mit Pflicht-CI, Dependabot (`package-ecosystem: pub`) und Secret Scanning aktivieren.

### F-025 · P3 · freeze-relevant: nein · Aufwand: S
**Kriterium:** ERR-05
**Ort:** `packages/trooper/lib/src/concurrency/query_queue.dart:62`, `controller/trooper_controller.dart:258,315,440,588`
**Befund:** Fehlermeldungen nennen meist, was schiefging, aber nicht, wie man es behebt. `QueryTrooper.get` nach
`dispose` meldet „Cannot execute request on a disposed TrooperQueryQueue“, nennt also eine interne Komponente statt
des Troopers und seines Namespace. Die Pflichtangabe „fetch oder cancellableFetch“ in den Controller-Fabriken wird nur
per `assert` geprüft; im Release-Build führt sie zu einem unspezifischen Null-Fehler (API-Aspekt → Task 10).
**Nachweis:** Code-Review der 8 `throw`- und 6 `assert`-Stellen in `lib/`
**Empfehlung:** Meldungen um Namespace und Abhilfe ergänzen; Pflichtangaben zur Laufzeit mit `ArgumentError` prüfen.

### F-036 · P3 · freeze-relevant: nein · Aufwand: S
**Kriterium:** OBS-02
**Ort:** `packages/trooper/lib/src/telemetry/trooper_logger.dart`
**Befund:** Der Logger ist über das Interface `TrooperLogger` austauschbar. Log-Level oder Filter (z. B. nur Fehler)
gibt es nicht; `ConsoleTrooperLogger` gibt jedes Event aus.
**Nachweis:** Code-Review
**Empfehlung:** Optionalen Filter (`bool Function(TrooperEvent)`) oder Level im `ConsoleTrooperLogger` anbieten.

### F-042 · P3 · freeze-relevant: nein · Aufwand: S
**Kriterium:** PERF-03
**Ort:** Keyed-Troopers (`invalidateKeys`, `removeWhere`, `currentDataMap` …), `telemetry/telemetry_hub.dart`
**Befund:** Ohne Listener am `TelemetryHub` verhindert der `hasListeners`-Guard Events, der Overhead ist damit
vernachlässigbar; mit einem Listener kostet ein Cache-Hit 8,2 % mehr. Die Komplexität der Keyed-Operationen
(z. B. Iteration über alle Keys) ist nirgends dokumentiert.
**Nachweis:** `docs/audit/raw/telemetry_overhead.txt` (`benchmark/audit_telemetry_overhead.dart`)
**Empfehlung:** Komplexität in der Dartdoc der Keyed-Operationen angeben.

### F-051 · P3 · freeze-relevant: nein · Aufwand: S
**Kriterium:** COMPAT-04
**Ort:** `packages/trooper/lib/src/telemetry/telemetry_hub.dart` (`TelemetryHub.global`), `CacheStore`, `TrooperQueryQueue`
**Befund:** Nirgends ist dokumentiert, dass Cache, Queues und der globale Telemetrie-Hub pro Isolate existieren und
Daten nicht zwischen Isolates geteilt werden (etwa bei Hintergrundverarbeitung mit `Isolate.run`).
**Nachweis:** Review von Doku und Dartdoc
**Empfehlung:** Kurzen Abschnitt zu Isolates in den Garantien (F-048) ergänzen.

### F-053 · P3 · freeze-relevant: nein · Aufwand: S
**Kriterium:** REL-04
**Ort:** pub.dev
**Befund:** Beide Pakete sind noch nicht veröffentlicht; ob sie unter einem verifizierten Publisher erscheinen, lässt
sich nicht prüfen. `homepage: https://parceapp.de` ist erreichbar.
**Nachweis:** `docs/audit/raw/linkcheck.txt` (pub.dev 404)
**Empfehlung:** Vor dem ersten Release einen verifizierten Publisher für `parceapp.de` anlegen und beide Pakete darunter veröffentlichen.
