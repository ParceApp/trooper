# Enterprise-Readiness-Audit für `trooper` und `trooper_bloc` – Prüfrahmen

- **Datum:** 2026-10-18
- **Status:** Entwurf zur Freigabe
- **Branch:** `audit/1.0`
- **Geprüfte Packages:** `packages/trooper` (`0.1.0-beta.1`), `packages/trooper_bloc` (`0.1.2-beta.1`)

## 1. Zielbild

Beide Packages werden als **1.0.0 auf pub.dev** für fremde Teams veröffentlicht. Die Public API wird mit 1.0.0
eingefroren; danach gilt striktes SemVer mit Deprecation-Policy und automatisiertem API-Diff-Check.

Dieses Dokument definiert, **wie** geprüft wird, ob die Packages dafür bereit sind. Es definiert nicht die Fixes.

### Scope

- **Im Scope:** beide Packages inkl. `lib/`, `test/`, `example/`, `benchmark/`, README, CHANGELOG, `skills/`,
  Workspace-Root-Dateien (README, `analysis_options.yaml`, `pubspec.yaml`), Repository-Governance.
- **Nicht im Scope:** `docs/animation/` (nur bzgl. Paketgröße, REL-03), Implementierung der Fixes (eigener Plan).

### Grundsätze

1. **Read-only gegenüber Produktivcode.** Die Prüfung ändert nichts in `packages/*/lib/`.
2. **Nachweis statt Meinung.** Jeder Status hat einen Nachweis: Toolausgabe, Testlauf oder `Datei:Zeile`.
3. **Hypothesen werden verifiziert.** Mit 🔎 markierte Vermutungen (Abschnitt 5) gelten erst nach Bestätigung durch
   einen Prüftest oder Tool-Nachweis als Finding.
4. **Reproduzierbar.** Commit-SHA und Tool-Versionen werden festgehalten; der Katalog liegt maschinenlesbar vor.

## 2. Bewertungsmodell

### 2.1 Kriterium

Jedes Kriterium hat:

| Feld | Bedeutung |
|---|---|
| ID | `<DIMENSION>-<NN>`, z. B. `API-03` |
| Priorität | **M** Must · **S** Should · **C** Could |
| Kriterium | prüfbare Aussage |
| Nachweis | Befehl, Tool oder Review-Methode, mit der geprüft wird |
| Schwelle | wann das Kriterium als erfüllt gilt |

**Status je Kriterium:** `erfüllt` · `teilweise` · `nicht erfüllt` · `n/a` (mit Begründung).

### 2.2 Reifegrad je Dimension (0–3)

| Grad | Bedeutung |
|---|---|
| 0 | fehlt |
| 1 | ad hoc vorhanden |
| 2 | vorhanden, mit Lücken (alle Must mindestens `teilweise`) |
| 3 | alle Must `erfüllt` und automatisiert in CI abgesichert |

### 2.3 Schweregrad von Findings

| Stufe | Bedeutung |
|---|---|
| **P0** | Korrektheitsbug, Datenverlust, Sicherheitslücke, Ressourcenleck – blockiert sofort |
| **P1** | muss vor 1.0 behoben sein; insbesondere alles, was nach dem API-Freeze nicht mehr ohne Major-Bump änderbar ist |
| **P2** | sollte behoben werden, darf in 1.x nachgeliefert werden |
| **P3** | nice to have |

Jedes Finding trägt zusätzlich das Flag **freeze-relevant** (ja/nein): Ist eine Behebung nach 1.0 ein Breaking Change?
Ein freeze-relevantes Finding ist mindestens P1.

### 2.4 Score

- Score je Dimension = Anteil erfüllter Kriterien, gewichtet M = 3, S = 2, C = 1; `teilweise` zählt halb, `n/a` entfällt.
- Gesamtscore = gewichteter Mittelwert der Dimensionen; **ASYNC, LIFE, ERR, API** zählen doppelt.
- Der Score macht Fortschritt sichtbar. **Über die Freigabe entscheidet ausschließlich das Gate (2.5).**

### 2.5 1.0-Release-Gate

Alle Bedingungen müssen gleichzeitig erfüllt sein:

1. Alle Must-Kriterien `erfüllt` (oder begründet `n/a`).
2. Keine offenen P0- oder P1-Findings.
3. Jede Dimension Reifegrad ≥ 2; **API, ASYNC, LIFE, ERR, COMPAT** Reifegrad 3. MARKET ist vom Gate ausgenommen.
4. Harte Schwellen:

| Schwelle | Wert |
|---|---|
| pana | 160/160 für beide Packages |
| `dart pub publish --dry-run` | 0 Warnungen für beide Packages |
| Analyzer | 0 Issues mit `very_good_analysis` + `strict-casts`, `strict-inference`, `strict-raw-types` |
| Dartdoc | 100 % der Public API dokumentiert; `dart doc` ohne Warnungen |
| Line-Coverage | `trooper` ≥ 95 %, `trooper_bloc` ≥ 90 % |
| Branch-Coverage | `trooper` ≥ 85 % |
| Mutation-Score | `trooper` (Module `core`, `concurrency`, `storage`, `controller`) ≥ 75 % |
| Flakiness | 100 aufeinanderfolgende Läufe mit zufälliger Testreihenfolge ohne Fehler |
| CI-Matrix | grün auf: Dart min-SDK, stable, beta; `trooper` zusätzlich auf VM, Chrome (dart2js), Chrome (dart2wasm); `trooper_bloc` auf min-Flutter und stable |
| API-Diff | Baseline 1.0 eingefroren, Diff-Check in CI blockiert Breaking Changes ohne Major-Bump |
| Benchmarks | Baseline gespeichert; CI schlägt bei > 10 % Regression an |

## 3. Kriterienkatalog

### FEAT – Feature-Verifikation (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| FEAT-01 | M | Feature-Inventar aus README (Root + Packages), CHANGELOG, Dartdoc und `skills/*/SKILL.md`; jedes Feature ist einem belegenden Test zugeordnet | Traceability-Matrix `docs/audit/traceability.md` | 100 % der Claims haben ≥ 1 belegenden Test oder werden als Finding geführt |
| FEAT-02 | M | SWR ohne Flackern: beim Refresh verschwinden vorhandene Daten nie aus dem State | Prüftest auf vollständige Zustandsfolge (Query, KeyedQuery, Stream) | Kein Zustand ohne Daten zwischen `loaded` und neuem `loaded` |
| FEAT-03 | M | Request-Coalescing: N parallele Aufrufe auf denselben Slot → genau 1 Fetch, auch bei Keyed-Varianten und über Controller-Grenzen | Bestehende Tests + Prüftest mit Aufrufzähler | Fetch-Zähler = 1 bei N ∈ {2, 50} |
| FEAT-04 | M | Jeder Wert jeder Policy (`StalePolicy`, `RetryPolicy`, `QueryConflictPolicy`) ist getestet | Abgleich Enum-/Klassenwerte ↔ Tests | 100 % der Werte getestet |
| FEAT-05 | M | L1/L2-Zusammenspiel: Kaltstart aus L2, Write-through, Invalidierung beider Ebenen | Review + Prüftest mit `MockStorageBackend` | Alle drei Pfade belegt |
| FEAT-06 | M | `trooper_bloc`: Snapshot-Locking und Microtask-Batching verhalten sich wie dokumentiert | Prüftest auf Zustandsfolge bei gleichzeitigen Source-Updates | Genau eine Transition pro Batch; keine gemischten Snapshots |
| FEAT-07 | S | `example/`, README-Snippets und Dartdoc-Beispiele kompilieren | Snippets extrahieren und analysieren | 0 Analyzer-Fehler |

### ASYNC – Nebenläufigkeit (Gewicht 2)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| ASYNC-01 | M | Eine ältere Antwort überschreibt nie eine neuere (pro Slot und pro Key) | Prüftest mit kontrollierten Completern in umgekehrter Reihenfolge | Endzustand = neueste Antwort, für alle Trooper-Typen |
| ASYNC-02 | M | Invalidate/Refetch/Mutate während eines laufenden Requests hat ein definiertes und dokumentiertes Ergebnis | Review + Prüftest je Kombination | Verhalten dokumentiert und getestet |
| ASYNC-03 | M | Keine unbehandelten asynchronen Fehler | Lints `unawaited_futures`, `discarded_futures`; Tests unter `runZonedGuarded` bzw. Prüfung auf Zone-Fehler | 0 Lint-Treffer ohne Begründung; 0 Zone-Fehler in der Suite |
| ASYNC-04 | M | Re-Entrancy: Listener, die während einer Benachrichtigung mutieren, disposen oder abonnieren, brechen nichts | Prüftest je Notify-Pfad | Kein Fehler, keine verlorenen Updates, keine Endlosschleife |
| ASYNC-05 | M | `CancelToken`: Abbruch propagiert; danach kein State-Update | Prüftest | 0 State-Updates nach Cancel |
| ASYNC-06 | M | `TrooperMutationQueue`: Reihenfolgegarantie dokumentiert und getestet; Optimistic Update mit Rollback bei Fehler | Review + Prüftest | Garantie dokumentiert; Rollback stellt exakt den Vorzustand her |
| ASYNC-07 | S | Stresstest mit randomisierten Interleavings | Seeded `fake_async`-Test, ≥ 1.000 Seeds | Invarianten (keine veralteten Daten, kein Leck) halten für alle Seeds |

### LIFE – Lifecycle und Ressourcen (Gewicht 2)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| LIFE-01 | M | `dispose` ist idempotent; jede öffentliche Methode hat nach `dispose` dokumentiertes Verhalten | Review + Prüftest je öffentlichem Typ | Dokumentiert und getestet |
| LIFE-02 | M | Keine Lecks: StreamController geschlossen, Timer gecancelt, Subscriptions beendet | Prüftest, der offene Ressourcen nach `dispose` zählt; `leak_tracker_flutter_testing` in `trooper_bloc` | 0 offene Ressourcen; 0 Leak-Meldungen |
| LIFE-03 | M | Speicher ist begrenzt (Größenlimit/LRU) oder Unbegrenztheit ist dokumentiert und konfigurierbar | Review `CacheStore`, Keyed-Maps | Begrenzung vorhanden oder explizit dokumentiert |
| LIFE-04 | M | `TrooperController.dispose` kaskadiert auf alle Troopers, auch mit laufenden Requests | Prüftest | Alle Kinder disposed; laufende Requests schreiben nicht mehr |
| LIFE-05 | S | Soak-Test: 10.000 Keys, 1 Mio. Operationen | Skript mit Speichermessung | Speicher nach GC stabil (±5 % nach Warm-up) |

### ERR – Fehlerbehandlung (Gewicht 2)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| ERR-01 | M | Sealed Exception-Hierarchie; Fehler aus Fetch, Codec, Storage, Timeout und Cancel sind unterscheidbar | Review `trooper_exception.dart` | Jede Quelle hat einen eigenen, per Pattern-Matching unterscheidbaren Typ |
| ERR-02 | M | Kein stilles `catch`; jeder Fehler landet im State oder in der Telemetrie; StackTraces bleiben erhalten | `grep` auf `catch` + Review jeder Stelle | 0 verschluckte Fehler |
| ERR-03 | M | Retry: Backoff, Jitter, Maximalzahl, nicht wiederholbare Fehler | Prüftest mit `fake_async` auf exakte Zeitpunkte | Zeitpunkte und Versuchszahl exakt wie konfiguriert |
| ERR-04 | M | L2-Migration: ältere, unbekannte, korrupte Einträge werden migriert oder sicher verworfen | Prüftest mit präparierten Envelopes | Kein Absturz, kein falsch typisierter State |
| ERR-05 | S | Fehlermeldungen sagen was, warum und wie man es behebt | Review aller `throw`-Stellen | Alle öffentlich sichtbaren Meldungen handlungsleitend |

### API – Public API (Gewicht 2)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| API-01 | M | Jedes exportierte Symbol ist begründet; Interna sind nicht exportiert | `dart_apitool extract` → Inventar mit Begründung je Symbol | 100 % begründet |
| API-02 | M | Jede öffentliche Klasse hat einen bewusst gewählten Modifier (`final`, `base`, `interface`, `sealed`, `abstract interface` …) | Skript zählt Klassen ohne Modifier | 0 Klassen ohne bewusste Entscheidung |
| API-03 | M | Konsistente Konventionen; Keyed-/Non-Keyed-Paare symmetrisch | Review: Paare gegenüberstellen (Methodennamen, Parameter, Rückgabetypen) | Abweichungen begründet |
| API-04 | M | Deprecation-Policy dokumentiert (≥ 1 Minor mit `@Deprecated` + Migrationshinweis vor Entfernung) | Dokument im Repo | vorhanden und im README verlinkt |
| API-05 | M | 1.0-Baseline + API-Diff-Check in CI | `dart_apitool diff` in CI | blockiert Breaking Changes ohne Major-Bump |
| API-06 | M | Re-Export-Strategie von `trooper_bloc` festgelegt, inkl. Versionsregel zwischen beiden Packages | Review `trooper_bloc.dart` + Dokument | Entscheidung dokumentiert |
| API-07 | S | Kein `dynamic` in der Public API; State-Objekte sind immutable mit `==`/`hashCode` | `dart_apitool`-Inventar + Review | 0 `dynamic` ohne Begründung; State-Typen immutable |

### ARCH – Architektur (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| ARCH-01 | M | `trooper` frei von Flutter und `dart:io` | `grep` + Web-Compile in CI | 0 Treffer; Web-Tests grün |
| ARCH-02 | M | Keine Import-Zyklen in `src/`; Schichtregel definiert und automatisiert | `lakos` | 0 Zyklen; Regel in CI |
| ARCH-03 | S | Dateien > 500 Zeilen begründet oder zerlegt | `wc -l` / `dart_code_linter` | Jede solche Datei hat Begründung oder Finding |
| ARCH-04 | S | Duplikation zwischen Keyed-/Non-Keyed-Varianten gemessen; Konsolidierung wo sinnvoll | Review + Duplikationsmessung | Ergebnis dokumentiert |
| ARCH-05 | M | Erweiterungspunkte (`StorageBackend`, `TrooperCodec`, `TrooperLogger`) mit stabilem Vertrag und Contract-Test-Kit | Review | Vertrag dokumentiert; wiederverwendbares Test-Kit exportiert |
| ARCH-06 | C | ADRs für Kernentscheidungen | Repo | vorhanden |

### TEST – Testqualität (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| TEST-01 | M | Coverage-Schwellen (2.5) in CI erzwungen | `package:coverage` / `flutter test --coverage --branch-coverage` | Schwellen erreicht und in CI |
| TEST-02 | M | Mutation-Score (2.5) | `mutation_test` auf Kernmodulen | ≥ 75 % |
| TEST-03 | M | Keine Flakes; keine echten Delays in Tests | 100 Läufe mit `--test-randomize-ordering-seed=random`; `grep` auf `Future.delayed`/`sleep` außerhalb `fake_async` | 0 Fehler; 0 echte Delays ohne Begründung |
| TEST-04 | M | Öffentliche Test-Utilities (`trooper_bloc/testing.dart`, `FakeAccessor`) getestet und dokumentiert; Bedarf für Core-Test-Helfer geprüft | Review | getestet, dokumentiert, Entscheidung zu Core-Helfern |
| TEST-05 | S | Property-Based-Tests für Invarianten von Cache und Queues | Review | vorhanden für `CacheStore`, `TrooperQueryQueue`, `TrooperMutationQueue` |

### QUAL – Code-Qualität (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| QUAL-01 | M | `very_good_analysis` + Strict-Modes | `dart analyze` mit Overlay-Konfiguration | 0 Issues |
| QUAL-02 | M | Formatierung | `dart format --set-exit-if-changed .` | Exit 0 |
| QUAL-03 | S | Zyklomatische Komplexität ≤ 15 pro Methode; kein toter Code | `dart_code_linter` | Überschreitungen begründet |

### PERF – Performance (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| PERF-01 | M | Benchmarks decken Hot Paths ab: Cache-Hit, SWR, Coalescing, Keyed mit 10.000 Keys, `trooper_bloc`-Derivation | Review `benchmark/` | alle fünf Pfade vorhanden |
| PERF-02 | M | Baseline + Regressionsschranke in CI | Benchmark-Lauf + gespeicherte Werte | > 10 % Regression schlägt fehl |
| PERF-03 | S | Komplexität der Keyed-Operationen dokumentiert; abgeschaltete Telemetrie ohne messbaren Overhead; Rebuilds pro Update gemessen | Benchmark + Doku | dokumentiert; Telemetrie-Overhead < 2 % |

### SEC – Sicherheit und Datenschutz (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| SEC-01 | M | L2-Persistenz: Klartext-Speicherung dokumentiert; Hook für Verschlüsselung vorhanden | Review `StorageBackend`, `TrooperCodec`, Doku | dokumentiert + Hook |
| SEC-02 | M | Logger/Telemetrie geben standardmäßig keine Payloads oder PII aus | Review `telemetry/` | Default ohne Payload |
| SEC-03 | M | Manipulierte L2-Daten führen nicht zum Absturz; Typen werden geprüft | Prüftest (vgl. ERR-04) | kein Absturz, kein falscher Typ |
| SEC-04 | M | `SECURITY.md` mit Meldeprozess; OSV-Scan der Abhängigkeiten in CI | `osv-scanner --lockfile pubspec.lock` | 0 bekannte Schwachstellen; Datei vorhanden |

### COMPAT – Kompatibilität (Gewicht 1, Gate verlangt Reifegrad 3)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| COMPAT-01 | M | Min-SDK und untere Abhängigkeitsgrenzen getestet; Ranges so weit wie sinnvoll | `dart pub downgrade` + Tests | grün |
| COMPAT-02 | M | `trooper` läuft auf VM, dart2js, dart2wasm | `dart test`, `dart test -p chrome`, `dart test -p chrome --compiler dart2wasm` | alle grün |
| COMPAT-03 | M | SDK-Constraints konsistent (Dart- vs. Flutter-Untergrenze) | Review `pubspec.yaml` | Flutter-Untergrenze bringt mindestens die Dart-Untergrenze mit |
| COMPAT-04 | S | Verhalten bei Nutzung mit Isolates dokumentiert | Doku | vorhanden |

### DOC – Dokumentation (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| DOC-01 | M | 100 % Dartdoc der Public API, Beispiele für Kern-APIs | Lint `public_member_api_docs`; `dart doc` | 0 fehlende Docs; 0 Warnungen |
| DOC-02 | M | READMEs korrekt und konsistent (Badges, Links, SDK-Angaben, Tooling-Claims) | Review + Linkcheck | 0 falsche Angaben; 0 tote oder lokale Links |
| DOC-03 | M | Getting Started, Konzepte, Rezepte, FAQ | Review | vorhanden |
| DOC-04 | M | Garantien explizit dokumentiert: Reihenfolge, Dispose, Fehler, Threading | Review | eigener Abschnitt vorhanden |
| DOC-05 | M | CHANGELOG nach Keep a Changelog; Migrationsleitfaden 0.x → 1.0 | Review | vorhanden |
| DOC-06 | S | Agent-Skills synchron zur API; Snippets analysierbar | Snippets extrahieren + analysieren | 0 Fehler |

### REL – Release (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| REL-01 | M | pana und Dry-Run | `pana`, `dart pub publish --dry-run` | 160/160; 0 Warnungen |
| REL-02 | M | Versionsstrategie im Monorepo (Lockstep vs. unabhängig) festgelegt; Publish per Tag via GitHub OIDC automatisiert | Doku + Workflow | vorhanden |
| REL-03 | M | Paketinhalt geprüft: keine großen Medien, keine lokalen Pfade | Dry-Run-Dateiliste, `.pubignore` | keine unnötigen Dateien |
| REL-04 | S | Verifizierter Publisher auf pub.dev | pub.dev | vorhanden |

### GOV – Governance und CI (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| GOV-01 | M | CI-Pipeline: analyze, format, test, coverage, Matrix, API-Diff, Benchmark | `.github/workflows/` | alle Schritte vorhanden und grün |
| GOV-02 | M | CONTRIBUTING, CODE_OF_CONDUCT, Issue- und PR-Templates | Repo | vorhanden |
| GOV-03 | M | Support-Policy (unterstützte SDK-Versionen, Pflegedauer 1.x) | Doku | vorhanden |
| GOV-04 | S | Dependabot, Branch-Protection | Repo-Einstellungen | aktiv |

### OBS – Observability (Gewicht 1)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| OBS-01 | S | Event-Katalog stabil und dokumentiert (gehört zur Public API und fällt unter den Freeze) | Review `trooper_event.dart` | jedes Event dokumentiert |
| OBS-02 | S | Logger austauschbar, mit Log-Level | Review | vorhanden |
| OBS-03 | C | DevTools-Extension | – | vorhanden |

### MARKET – Marktvergleich (optional, nicht gate-relevant)

| ID | P | Kriterium | Nachweis | Schwelle |
|---|---|---|---|---|
| MARKET-01 | C | Feature-Gap gegenüber TanStack Query, Riverpod, cached_query | Recherche | Gap-Liste vorhanden |

## 4. Methode

### 4.1 Rahmen

- Arbeitsort: eigener Worktree auf Branch `audit/1.0`.
- Temporäre Konfigurationen (z. B. strengere `analysis_options.yaml`) und Prüftests existieren nur auf diesem Branch.
- Tools werden global installiert (`dart pub global activate …`), nicht als Dependency.
- Festgehalten werden: Commit-SHA des geprüften Stands, Versionen von Dart, Flutter, Chrome und allen Tools
  (Stand bei Erstellung dieses Dokuments: Dart 3.13.5, Flutter 3.47.6).

### 4.2 Phase 1 – Automatisierte Baseline

Rohausgaben nach `docs/audit/raw/` (gitignored).

| Kriterien | Tool / Befehl |
|---|---|
| QUAL-01, QUAL-02, ASYNC-03 | `dart analyze` mit `very_good_analysis`-Overlay + Strict-Modes; `dart format --set-exit-if-changed .` |
| TEST-01 | `dart test --coverage` + `package:coverage` (Branch-Coverage); `flutter test --coverage --branch-coverage` |
| TEST-02 | `mutation_test` auf `src/core`, `src/concurrency`, `src/storage`, `src/controller` |
| TEST-03 | Schleife über 100 Läufe mit `--test-randomize-ordering-seed=random` |
| COMPAT-01, COMPAT-02 | `dart pub downgrade` + Tests; `dart test -p chrome`; `dart test -p chrome --compiler dart2wasm` |
| API-01, API-02, API-05, API-07 | `dart_apitool extract`; Skript zur Zählung der Klassen-Modifier |
| ARCH-02, ARCH-03, QUAL-03 | `lakos`; `dart_code_linter` |
| REL-01, REL-03, DOC-01 | `pana`; `dart pub publish --dry-run`; `dart doc`; Lint `public_member_api_docs` |
| SEC-04 | `osv-scanner --lockfile pubspec.lock` |
| PERF-01, PERF-02 | bestehenden Benchmark ausführen; Baseline sichern |
| LIFE-02 | `leak_tracker_flutter_testing` in `trooper_bloc`-Tests |

### 4.3 Phase 2 – Manuelles Deep-Review

Reihenfolge: **ASYNC → LIFE → ERR → API**, danach die übrigen Dimensionen. Je Modul:

1. Code lesen.
2. Zugesicherte Garantie formulieren (aus Dartdoc/README oder implizit).
3. Garantie mit einem **Prüftest** belegen oder widerlegen.

Prüftests liegen unter `packages/<pkg>/test/audit/`, tragen das Tag `audit` und referenzieren die Kriteriums-ID.
Ein roter Prüftest ist Nachweis eines Findings; er wird mit `skip: '<FINDING-ID>'` markiert, damit die reguläre Suite
grün bleibt. Prüftests dienen in der Fix-Phase als Regressionstests.

### 4.4 Phase 3 – Feature-Traceability

Alle Feature-Claims aus READMEs, CHANGELOG, Dartdoc und `SKILL.md` sammeln; je Claim belegenden Test zuordnen oder
als fehlend markieren (FEAT-01).

### 4.5 Phase 4 – Bewertung

Status und Nachweis je Kriterium in `criteria.yaml`; Skript berechnet Score, Reifegrade und Gate-Status;
Findings in `findings.md`; Report in `REPORT.md`.

### 4.6 Phase 5 – Fix-Roadmap (nicht Teil der Prüfung)

Aus den Findings entsteht ein eigener Umsetzungsplan mit eigener Freigabe.

### 4.7 Parallelisierung

Phase 1 und die Dimensionsgruppen in Phase 2 sind voneinander unabhängig. Ob sie parallel ausgeführt werden, wird im
Ausführungsplan entschieden; Standard ist sequenziell.

## 5. Hypothesen aus der Vorab-Sichtung (🔎, zu verifizieren)

| Kriterium | Beobachtung |
|---|---|
| LIFE-03 | `CacheStore` kennt nur TTL-Eviction mit optionalem Timer (`evictionInterval`), keine Größengrenze |
| ERR-04 | `StorageEnvelope.fromJson` liest einen Eintrag ohne `version` als `currentVersion` |
| API-02 | 46 Klassendeklarationen in `lib/` ohne Klassen-Modifier |
| API-06 | `trooper_bloc` re-exportiert `trooper` vollständig sowie `Emitter` aus `flutter_bloc` |
| QUAL-01, DOC-02 | `analysis_options.yaml` nutzt `package:lints/recommended.yaml`; README behauptet `very_good_analysis` |
| COMPAT-03 | `trooper_bloc`: `flutter: ">=3.24.0"` (bringt Dart 3.5) vs. `sdk: ^3.12.0` |
| DOC-02 | Root-README: Badge „Dart 3.5+“ vs. `sdk: ^3.12.0`; Links auf `file:///Users/hannes/...` |
| GOV-01 | kein `.github/`-Verzeichnis, keine CI |
| ARCH-03 | `trooper_controller.dart` (869 Zeilen), `keyed_stream_trooper.dart` (807 Zeilen) |

## 6. Deliverables

| Datei | Inhalt | Nach `main` |
|---|---|---|
| `docs/superpowers/specs/2026-10-18-enterprise-readiness-audit-design.md` | dieser Prüfrahmen | ja |
| `docs/audit/REPORT.md` | Executive Summary, Gate-Status mit Begründung, Reifegrad-Tabelle, Gesamtscore, Top-10-Findings, Empfehlung | ja |
| `docs/audit/criteria.yaml` | Katalog mit Status und Nachweis je Kriterium (Schema 6.1) | ja |
| `docs/audit/findings.md` | Findings mit ID, Schwere, Kriterium, `Datei:Zeile`, Beschreibung, Nachweis, Empfehlung, Aufwand S/M/L, freeze-relevant | ja |
| `docs/audit/traceability.md` | Feature-Matrix: Claim, Quelle, belegender Test, Status | ja |
| `docs/audit/raw/` | Rohausgaben der Tools | nein (gitignored) |
| `packages/*/test/audit/` | Prüftests mit Tag `audit` | erst in der Fix-Phase |

Optional nach Abschluss: privates, teilbares HTML-Dashboard (Gate-Status, Reifegrade, filterbare Findings).

### 6.1 Schema `criteria.yaml`

```yaml
meta:
  audited_commit: <sha>
  date: 2026-10-18
  tools: { dart: 3.13.5, flutter: 3.47.6, pana: <version>, ... }
dimensions:
  - id: ASYNC
    weight: 2
    gate_min_maturity: 3
    criteria:
      - id: ASYNC-01
        priority: M          # M | S | C
        status: not_met      # met | partial | not_met | na
        evidence: packages/trooper/test/audit/out_of_order_test.dart
        findings: [F-012]
        note: <optional>
```

### 6.2 Format eines Findings

```markdown
### F-012 · P1 · freeze-relevant: nein · Aufwand: M
**Kriterium:** ASYNC-01
**Ort:** packages/trooper/lib/src/core/keyed_query_trooper.dart:212
**Befund:** …
**Nachweis:** packages/trooper/test/audit/out_of_order_test.dart (rot)
**Empfehlung:** …
```
