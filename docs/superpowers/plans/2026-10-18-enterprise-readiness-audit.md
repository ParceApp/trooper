# Enterprise-Readiness-Audit – Ausführungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beide Packages (`trooper`, `trooper_bloc`) gegen den freigegebenen Prüfrahmen auditieren und als Ergebnis
Report, Kriterienstatus, Findings und Traceability-Matrix liefern, inklusive einer Gate-Entscheidung für 1.0.0.

**Architecture:** Ein kleines, eigenständiges Dart-Tool unter `tool/audit/` (nicht Teil des Workspace) lädt den
Katalog `docs/audit/criteria.yaml` und berechnet Score, Reifegrade und Gate. Shell-Skripte unter `tool/audit/scripts/`
führen die automatisierten Checks aus und schreiben Rohausgaben nach `docs/audit/raw/`. Prüftests unter
`packages/*/test/audit/` belegen oder widerlegen die zugesicherten Garantien.

**Tech Stack:** Dart 3.13.5, Flutter 3.47.6, `package:test`, `fake_async`, `package:yaml`; global aktivierte Tools:
`coverage`, `pana`, `dart_apitool`, `lakos`, `dart_code_linter`, `mutation_test`; `osv-scanner` (Homebrew).

**Spec:** `docs/superpowers/specs/2026-10-18-enterprise-readiness-audit-design.md`

## Global Constraints

- Branch: `audit/1.0`. Arbeitet der Executor in einem Worktree, zuerst im Haupt-Checkout `git switch main`
  (der Branch ist dort aktuell ausgecheckt).
- **Read-only:** Nichts unter `packages/trooper/lib/` und `packages/trooper_bloc/lib/` wird verändert.
- Temporäre Änderungen an `analysis_options.yaml` und `pubspec.lock` werden von dem Skript, das sie verursacht,
  wiederhergestellt.
- Erlaubte Änderungen an Packages: nur `test/audit/`, `dart_test.yaml`, `test/flutter_test_config.dart` und die
  Dev-Dependency `leak_tracker_flutter_testing` in `trooper_bloc` (alles nur auf diesem Branch).
- Tools werden global aktiviert (`dart pub global activate <tool>`), nie als Dependency eines Packages.
- Rohausgaben nach `docs/audit/raw/` (gitignored). Jeder Lauf schreibt zusätzlich `<name>.exit` mit dem Exit-Code.
- Gate-Schwellen (Spec 2.5): pana 160/160 · Dry-Run 0 Warnungen · 0 Analyzer-Issues (VGA + strict) ·
  100 % Dartdoc · Line-Coverage `trooper` ≥ 95 %, `trooper_bloc` ≥ 90 % · Branch-Coverage `trooper` ≥ 85 % ·
  Mutation-Score ≥ 75 % · 100 Läufe ohne Flake · Benchmark-Regression > 10 % schlägt fehl.
- Prüftests nutzen ausschließlich `fake_async` oder `Completer` für Zeit und Reihenfolge, nie `Future.delayed`
  mit echter Zeit.
- Ein roter Prüftest wird mit `skip: 'F-NNN'` markiert, sobald das Finding angelegt ist; die Suite bleibt grün.
- Finding-IDs `F-001`, `F-002`, … werden fortlaufend vergeben und gleichzeitig in `criteria.yaml` (Liste `findings`)
  und `docs/audit/findings.md` (Format Spec 6.2) eingetragen.
- Commit-Messages enden mit `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Prüftest grün aus falschen Gründen** (echte Timer, Race im Test selbst) → Task 13 prüft per `grep`, dass
   `test/audit/` kein `Future.delayed` ohne `fake_async` enthält.
2. **Nicht bewertetes Kriterium zählt als bestanden** → Scorer-Test `pending criterion fails gate with exit 2` (Task 1).
3. **Audit verändert versehentlich `lib/`** → `guard.sh` (Task 1) läuft vor jedem Commit und in Task 13.
4. **Tool scheitert still** (Exit-Code ignoriert, leere Ausgabe) → `run_step` schreibt `<name>.exit`; Test
   `run_step records non-zero exit` (Task 2); Task 13 prüft alle `*.exit`.
5. **`pubspec.lock` oder `analysis_options.yaml` bleiben verändert** (Downgrade, Analyzer-Overlay) → Skripte
   stellen per `trap` wieder her; Verifikationsschritt `git status --porcelain` leer (Tasks 2, 3).

---

## Dateistruktur

| Datei | Verantwortung |
|---|---|
| `tool/audit/pubspec.yaml` | eigenständiges Paket `trooper_audit_tool` (kein Workspace-Mitglied), Deps: `yaml`; Dev: `test` |
| `tool/audit/lib/catalog.dart` | Modell und YAML-Parser für `criteria.yaml` |
| `tool/audit/lib/scoring.dart` | Score, Reifegrad, Gate |
| `tool/audit/lib/lcov.dart` | Coverage-Zusammenfassung aus lcov |
| `tool/audit/lib/class_modifiers.dart` | Erkennung öffentlicher Klassen ohne Modifier |
| `tool/audit/bin/score.dart` | CLI: Score und Gate ausgeben, `docs/audit/score.md` schreiben |
| `tool/audit/bin/lcov_summary.dart` | CLI zu `lcov.dart` |
| `tool/audit/bin/class_modifiers.dart` | CLI zu `class_modifiers.dart` |
| `tool/audit/test/*_test.dart` | Tests der Tool-Bibliotheken |
| `tool/audit/scripts/lib.sh` | `run_step` (Ausgabe + Exit-Code protokollieren) |
| `tool/audit/scripts/guard.sh` | bricht ab, wenn `packages/*/lib` gegenüber `main` verändert ist |
| `tool/audit/scripts/{env,static,tests,flake,compat,mutation,api_arch,release}.sh` | Phase-1-Läufe |
| `tool/audit/analysis_options.audit.yaml` | Analyzer-Overlay (VGA + strict) |
| `docs/audit/criteria.yaml` | Katalog mit Status (Schema Spec 6.1, Erweiterungen siehe Task 1) |
| `docs/audit/findings.md` · `traceability.md` · `api-inventory.md` · `REPORT.md` · `score.md` | Ergebnisse |
| `packages/trooper/test/audit/*_audit_test.dart` | Prüftests Core |
| `packages/trooper_bloc/test/audit/*_audit_test.dart` | Prüftests BLoC |
| `packages/trooper/benchmark/audit_soak.dart` | Soak-Test (LIFE-05) |

---

### Task 1: Audit-Tool, Katalog und Guard

**Files:**
- Create: `tool/audit/pubspec.yaml`, `tool/audit/lib/catalog.dart`, `tool/audit/lib/scoring.dart`,
  `tool/audit/bin/score.dart`, `tool/audit/test/scoring_test.dart`, `tool/audit/scripts/guard.sh`,
  `docs/audit/criteria.yaml`
- Modify: `.gitignore` (Zeile `docs/audit/raw/` anhängen)

**Interfaces:**
- Produces:
  - `enum Priority { must, should, could }` (YAML `M`/`S`/`C`)
  - `enum Status { met, partial, notMet, na }` (YAML `met`/`partial`/`not_met`/`na`; `null` = noch nicht bewertet)
  - `enum Severity { p0, p1, p2, p3 }` (YAML `P0`…`P3`)
  - `class Criterion { String id; Priority priority; Status? status; bool automatedInCi; String? evidence; List<String> findings; String? note; }`
  - `class Dimension { String id; int weight; int? gateMinMaturity; List<Criterion> criteria; }` (`gateMinMaturity == null` = nicht gate-relevant)
  - `class Finding { String id; Severity severity; String criterion; bool freezeRelevant; bool open; }`
  - `class Catalog { Map<String, Object?> meta; List<Dimension> dimensions; List<Finding> findings; }`
  - `Catalog parseCatalog(String yamlSource)`: wirft `FormatException` bei unbekannten Werten oder fehlenden Pflichtfeldern
  - `double? dimensionScore(Dimension d)`: `null`, wenn alle Kriterien `na` oder unbewertet sind
  - `int maturity(Dimension d)`
  - `double? totalScore(Catalog c)`
  - `class GateResult { bool passed; List<String> reasons; List<String> pending; }`
  - `GateResult evaluateGate(Catalog c)`
  - CLI `dart run tool/audit/bin/score.dart <criteria.yaml> [--out <md>]` → Exit 0 = Gate bestanden, 1 = nicht bestanden, 2 = unbewertete Kriterien vorhanden

**Regeln (aus Spec 2.2–2.5):**
- Score: Gewicht M = 3, S = 2, C = 1; Wert met = 1, partial = 0,5, not_met = 0; `na` und unbewertet entfallen.
- Gesamtscore: Mittelwert der Dimensionsscores, gewichtet mit `Dimension.weight`; Dimensionen mit Score `null` entfallen.
- Reifegrad: 3 = alle M-Kriterien `met`/`na` und alle `met`-M-Kriterien `automatedInCi`; 2 = alle M in {met, partial, na};
  1 = mindestens ein Kriterium `met` oder `partial`; sonst 0.
- Gate: (1) jedes M `met` oder `na`; (2) kein `Finding` mit `open && severity ∈ {p0, p1}`;
  (3) `maturity(d) >= d.gateMinMaturity` für jede Dimension mit `gateMinMaturity != null`;
  unbewertete Kriterien → `passed = false`, IDs in `pending`. Die harten Schwellen aus Spec 2.5 sind über ihre
  M-Kriterien abgebildet (REL-01, QUAL-01, DOC-01, TEST-01/02/03, COMPAT-01/02, API-05, PERF-02).

**Schema-Erweiterungen gegenüber Spec 6.1** (für die maschinelle Auswertung nötig): je Kriterium `automated_in_ci: bool`;
oberste Ebene `findings: [{id, severity, criterion, freeze_relevant, status: open|closed}]`.

- [ ] **Step 1: Paket anlegen und auflösen**

`tool/audit/pubspec.yaml` mit `name: trooper_audit_tool`, `publish_to: none`, `environment: sdk: ^3.12.0`,
`dependencies: yaml: ^3.1.0`, `dev_dependencies: test: ^1.25.0`, ohne `resolution: workspace`.

Run: `cd tool/audit && dart pub get`
Expected: `Got dependencies!`. Lehnt pub das Paket ab, weil es innerhalb des Workspace-Roots liegt, `tool/audit`
in der Root-`pubspec.yaml` unter `workspace:` eintragen, in `tool/audit/pubspec.yaml` `resolution: workspace`
ergänzen, `dart pub get` im Root ausführen und die Abweichung im Report unter „Tooling“ notieren.

- [ ] **Step 2: Failing tests schreiben** (`tool/audit/test/scoring_test.dart`)

Hilfsfunktion `Criterion c(String id, Priority p, Status? s, {bool ci = false})` und
`Dimension dim(String id, List<Criterion> cs, {int weight = 1, int? gate = 2})`.

```dart
test('dimensionScore weights priorities and halves partial', () {
  final d = dim('X', [c('X-01', Priority.must, Status.met), c('X-02', Priority.should, Status.partial),
      c('X-03', Priority.could, Status.notMet), c('X-04', Priority.must, Status.na)]);
  expect(dimensionScore(d), closeTo(4 / 6, 1e-9));
});
test('dimensionScore is null when all criteria are na', () {
  expect(dimensionScore(dim('X', [c('X-01', Priority.must, Status.na)])), isNull);
});
test('maturity levels', () {
  expect(maturity(dim('X', [c('X-01', Priority.must, Status.met, ci: true)])), 3);
  expect(maturity(dim('X', [c('X-01', Priority.must, Status.met)])), 2);
  expect(maturity(dim('X', [c('X-01', Priority.must, Status.partial, ci: true)])), 2);
  expect(maturity(dim('X', [c('X-01', Priority.must, Status.notMet), c('X-02', Priority.should, Status.met)])), 1);
  expect(maturity(dim('X', [c('X-01', Priority.must, Status.notMet)])), 0);
});
test('totalScore weights dimensions', () {
  final cat = Catalog(meta: {}, findings: [], dimensions: [
    dim('ASYNC', [c('A-01', Priority.must, Status.partial)], weight: 2),
    dim('FEAT', [c('F-01', Priority.must, Status.met)]),
  ]);
  expect(totalScore(cat), closeTo(2 / 3, 1e-9));
});
group('evaluateGate', () {
  // fullyMet(): every dimension's M criteria met + automatedInCi, no findings
  test('passes when everything is met and automated', () => expect(evaluateGate(fullyMet()).passed, isTrue));
  test('fails on unmet must and names it', () { /* ASYNC-01 notMet */ expect(r.passed, isFalse); expect(r.reasons.join(), contains('ASYNC-01')); });
  test('fails on open P1 finding', () { /* F-001 P1 open */ expect(r.reasons.join(), contains('F-001')); });
  test('closed P1 and open P2 do not block', () => expect(r.passed, isTrue));
  test('fails when COMPAT maturity 2 is below gate minimum 3', () => expect(r.reasons.join(), contains('COMPAT')));
  test('ignores dimension with gateMinMaturity null', () => expect(r.passed, isTrue)); // MARKET maturity 0
  test('pending criterion fails gate', () { expect(r.passed, isFalse); expect(r.pending, ['API-03']); });
});
test('parseCatalog rejects unknown priority', () {
  expect(() => parseCatalog(_yamlWithPriority('X')), throwsFormatException);
});
test('pending criterion fails gate with exit 2', () async {
  // writes a temp YAML with one status: null, runs bin/score.dart via Process.run
  expect(result.exitCode, 2);
});
```

- [ ] **Step 3: Tests laufen lassen** – Run: `cd tool/audit && dart test` · Expected: FAIL (Symbole nicht definiert)

- [ ] **Step 4: `catalog.dart`, `scoring.dart`, `bin/score.dart` implementieren** nach den Interfaces und Regeln oben.
`score.dart` gibt eine Markdown-Tabelle (Dimension, Score in %, Reifegrad, Gate-Minimum) plus Gesamtscore, Gate-Status,
Gründe und unbewertete IDs aus und schreibt sie mit `--out` zusätzlich in die Datei.

- [ ] **Step 5: Tests laufen lassen** – Run: `cd tool/audit && dart test` · Expected: alle PASS

- [ ] **Step 6: `docs/audit/criteria.yaml` anlegen**

Alle 74 Kriterien aus Spec Abschnitt 3 übertragen (ID, Priorität), jeweils `status: null`, `automated_in_ci: false`,
`evidence: null`, `findings: []`. Dimensionen und Gewichte: ASYNC, LIFE, ERR, API `weight: 2`, alle übrigen `1`.
`gate_min_maturity`: API, ASYNC, LIFE, ERR, COMPAT `3`; MARKET `null`; alle übrigen `2`. `findings: []` auf oberster Ebene.
`meta.audited_commit` = Ausgabe von `git rev-parse main`.

Run: `dart run tool/audit/bin/score.dart docs/audit/criteria.yaml`
Expected: Exit 2, 74 unbewertete IDs, davon 55 mit Priorität M (Kontrolle: Anzahl `priority: M` per `grep -c`).

- [ ] **Step 7: `guard.sh` anlegen**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if ! git diff --quiet main -- packages/trooper/lib packages/trooper_bloc/lib; then
  echo "GUARD: packages/*/lib differs from main" >&2; exit 1
fi
echo "GUARD: ok"
```

Run: `bash tool/audit/scripts/guard.sh` · Expected: `GUARD: ok`

- [ ] **Step 8: Commit**

```bash
git add tool/audit docs/audit/criteria.yaml .gitignore
git commit -m "audit: add scoring tool, criteria catalog and guard"
```

---

### Task 2: Phase 1 – Umgebung und statische Analyse

**Files:**
- Create: `tool/audit/scripts/lib.sh`, `tool/audit/scripts/env.sh`, `tool/audit/scripts/static.sh`,
  `tool/audit/analysis_options.audit.yaml`, `tool/audit/test/run_step_test.dart`

**Interfaces:**
- Produces: `run_step <name> <command...>` in `lib.sh`: führt den Befehl aus, schreibt stdout+stderr nach
  `docs/audit/raw/<name>.txt` und den Exit-Code nach `docs/audit/raw/<name>.exit`, gibt immer 0 zurück
  (damit ein Lauf weitere Schritte nicht abbricht).

- [ ] **Step 1: Failing test** (`run_step_test.dart`): ruft per `Process.run('bash', ['-c', 'source tool/audit/scripts/lib.sh; AUDIT_RAW=$tmp run_step demo false'])` auf.
  Assertions: `File('$tmp/demo.exit').readAsStringSync().trim() == '1'`, Prozess-Exit-Code `0`. Zweiter Test mit
  `true` → `.exit` enthält `0`.
- [ ] **Step 2: Run** `cd tool/audit && dart test test/run_step_test.dart` · Expected: FAIL (lib.sh fehlt)
- [ ] **Step 3: `lib.sh` implementieren**; Zielverzeichnis aus `AUDIT_RAW` (Default `docs/audit/raw`), wird angelegt.
- [ ] **Step 4: Run** wie Step 2 · Expected: PASS
- [ ] **Step 5: `env.sh`** schreibt per `run_step` nach `raw/env.txt`: `git rev-parse main`, `dart --version`,
  `flutter --version`, Chrome-Version (`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version`) und
  `dart pub global list`.
- [ ] **Step 6: Analyzer-Overlay** `analysis_options.audit.yaml`:

```yaml
include: package:very_good_analysis/analysis_options.yaml
analyzer:
  language: { strict-casts: true, strict-inference: true, strict-raw-types: true }
  exclude: [build/**, "**/build/**", tool/**]
linter:
  rules: { unawaited_futures: true, discarded_futures: true }
```

- [ ] **Step 7: `static.sh`**: `trap 'git checkout -- analysis_options.yaml' EXIT`; Overlay nach `analysis_options.yaml`
  kopieren; `run_step analyze_vga dart analyze --format=machine packages`; Zusammenfassung je Lint-Code
  (`cut -d'|' -f3 | sort | uniq -c | sort -rn`) nach `raw/analyze_vga_summary.txt`;
  `run_step format dart format --output=none --set-exit-if-changed packages`.
- [ ] **Step 8: Ausführen und verifizieren**

Run: `bash tool/audit/scripts/env.sh && bash tool/audit/scripts/static.sh && git status --porcelain analysis_options.yaml`
Expected: Rohdateien vorhanden, `git status` leer. Anzahl Issues, Top-Lints sowie Treffer für
`public_member_api_docs`, `unawaited_futures` und `discarded_futures` notieren.

- [ ] **Step 9: Kriterien eintragen**: QUAL-01, QUAL-02 bewerten (Schwelle Spec §3). ASYNC-03 und DOC-01 erhalten
  hier nur den Rohnachweis; bewertet werden sie in Task 7 bzw. Task 6. Findings anlegen (ein Finding pro
  Lint-Kategorie, nicht pro Treffer). Hypothese QUAL-01/DOC-02 (Spec §5) bestätigen oder verwerfen.
- [ ] **Step 10: Commit** `git add tool/audit docs/audit && git commit -m "audit: static analysis baseline"`

---

### Task 3: Phase 1 – Tests, Coverage, Flakiness, Kompatibilität

**Files:**
- Create: `tool/audit/lib/lcov.dart`, `tool/audit/bin/lcov_summary.dart`, `tool/audit/test/lcov_test.dart`,
  `tool/audit/scripts/tests.sh`, `tool/audit/scripts/flake.sh`, `tool/audit/scripts/compat.sh`

**Interfaces:**
- Produces: `class CoverageSummary { int lineHit, lineFound, branchHit, branchFound; double get linePct; double? get branchPct; }`,
  `CoverageSummary summarizeLcov(String lcov)`; CLI `dart run tool/audit/bin/lcov_summary.dart <lcov.info>` gibt
  `lines: 50.0% (1/2)` und `branches: 33.3% (1/3)` aus.

- [ ] **Step 1: Failing test** (`lcov_test.dart`)

```dart
test('summarizes DA and BRDA records, "-" counts as not taken', () {
  const lcov = 'SF:a.dart\nDA:1,1\nDA:2,0\nBRDA:1,0,0,1\nBRDA:1,0,1,0\nBRDA:1,0,2,-\nend_of_record\n';
  final s = summarizeLcov(lcov);
  expect([s.lineHit, s.lineFound, s.branchHit, s.branchFound], [1, 2, 1, 3]);
  expect(s.linePct, closeTo(50, 1e-9));
  expect(s.branchPct, closeTo(100 / 3, 1e-9));
});
test('branchPct is null without BRDA records', () {
  expect(summarizeLcov('SF:a.dart\nDA:1,1\nend_of_record\n').branchPct, isNull);
});
```

- [ ] **Step 2: Run** `cd tool/audit && dart test test/lcov_test.dart` · Expected: FAIL
- [ ] **Step 3: `lcov.dart` + CLI implementieren** (Zählung aus `DA`/`BRDA`-Zeilen, nicht aus `LF`/`LH`).
- [ ] **Step 4: Run** wie Step 2 · Expected: PASS
- [ ] **Step 5: `tests.sh`**
  - `trooper`: `dart pub global run coverage:test_with_coverage --branch-coverage --out ../../docs/audit/raw/coverage_trooper` (in `packages/trooper`)
  - `trooper_bloc`: `flutter test --coverage --branch-coverage --coverage-path ../../docs/audit/raw/coverage_bloc/lcov.info` (in `packages/trooper_bloc`)
  - beide Ergebnisse mit `lcov_summary` nach `raw/coverage_summary.txt`
  - echte Delays: `grep -rnE "Future(<void>)?\.delayed|sleep\(" packages/*/test` → `raw/real_delays.txt`
- [ ] **Step 6: `flake.sh`** (läuft im Hintergrund, Dauer protokollieren): je Package 100 Läufe mit
  `--test-randomize-ordering-seed=random` (`dart test --reporter=failures-only` bzw. `flutter test --reporter=failures-only`),
  fehlgeschlagene Läufe mit Seed als `RUN <i> FAILED seed=<seed>` nach `raw/flake_<pkg>.txt`.
- [ ] **Step 7: `compat.sh`**
  - Web: in `packages/trooper` `run_step web_js dart test -p chrome` und `run_step web_wasm dart test -p chrome --compiler dart2wasm`
  - Downgrade: `trap 'git checkout -- pubspec.lock && flutter pub get' EXIT`; im Root `flutter pub downgrade`, dann
    `run_step downgrade_trooper dart test` und `run_step downgrade_bloc flutter test`, aufgelöste Versionen nach
    `raw/downgrade_versions.txt` (`flutter pub deps --style=compact`)
- [ ] **Step 8: Ausführen und verifizieren**

Run: `bash tool/audit/scripts/tests.sh && bash tool/audit/scripts/compat.sh && git status --porcelain pubspec.lock`; `flake.sh` im Hintergrund
Expected: alle `.exit`-Dateien vorhanden, `git status` leer.

- [ ] **Step 9: Kriterien eintragen**: TEST-01 (Schwellen 95/85 bzw. 90), TEST-03 (Flakes und echte Delays),
  COMPAT-01, COMPAT-02, ARCH-01 (Web-Läufe). Findings anlegen. Fehlschläge in Web-Läufen, die nur von Test-Fixtures
  mit `dart:io` herrühren, als TEST-Finding führen, nicht als COMPAT-Finding.
- [ ] **Step 10: Commit** `git add tool/audit docs/audit && git commit -m "audit: tests, coverage, flakiness, compat baseline"`

---

### Task 4: Phase 1 – Mutation-Testing

**Files:**
- Create: `tool/audit/scripts/mutation.sh`, `tool/audit/mutation.xml`

- [ ] **Step 1: Tool aktivieren** `dart pub global activate mutation_test`; `dart pub global run mutation_test:mutation_test --help` lesen.
- [ ] **Step 2: `mutation.xml`** nach der Hilfe des Tools anlegen: eingebaute Regeln, Timeout 120 s pro Mutant und je
  Quelldatei ein **gezielter** Testbefehl (`dart test test/<passender Ordner>` in `packages/trooper`):
  `src/concurrency/*` → `test/concurrency test/edge_cases`; `src/storage/*` → `test/storage test/concurrency/cache_store_test.dart test/error`;
  `src/core/*` → `test/core test/edge_cases`; `src/controller/*` → `test/controller test/edge_cases`.
- [ ] **Step 3: Probelauf** auf `src/concurrency/cancel_token.dart`, Laufzeit pro Mutant messen und Gesamtlaufzeit
  hochrechnen.
  Expected: Report mit Mutation-Score für die Datei.
- [ ] **Step 4: Hauptlauf** im Hintergrund über alle Dateien der vier Module. Liegt die Hochrechnung über 8 Stunden,
  eine Stichprobe von 50 % der Mutanten je Datei ziehen (Option des Tools oder Dateiauswahl) und TEST-02 höchstens
  `partial` setzen, mit Begründung in `note`.
- [ ] **Step 5: Kriterium eintragen**: TEST-02 (Schwelle 75 %). Dateien mit Score < 60 % als Findings führen und die
  überlebenden Mutanten als Hinweise auf fehlende Assertions im Finding nennen.
- [ ] **Step 6: Commit** `git add tool/audit docs/audit && git commit -m "audit: mutation testing"`

---

### Task 5: Phase 1 – API-Inventar und Architekturmetriken

**Files:**
- Create: `tool/audit/lib/class_modifiers.dart`, `tool/audit/bin/class_modifiers.dart`,
  `tool/audit/test/class_modifiers_test.dart`, `tool/audit/scripts/api_arch.sh`

**Interfaces:**
- Produces: `class ClassDecl { String name; Set<String> modifiers; int line; }`,
  `List<ClassDecl> findClassDeclarations(String source)`, `bool hasApiModifier(ClassDecl d)` (wahr bei
  `final`, `base`, `interface` oder `sealed`); CLI gibt öffentliche Klassen ohne Modifier als `pfad:zeile Name` aus,
  am Ende `total: N`.

- [ ] **Step 1: Failing test**

```dart
test('finds public classes without API modifier, ignores private and doc comments', () {
  const src = 'class A {}\nfinal class B {}\nabstract class C {}\nabstract interface class D {}\n'
      'sealed class E {}\nbase class F {}\nclass _G {}\n/// class H {}\nmixin class I {}\n';
  final missing = findClassDeclarations(src).where((d) => !d.name.startsWith('_') && !hasApiModifier(d));
  expect(missing.map((d) => d.name), ['A', 'C', 'I']);
});
```

- [ ] **Step 2: Run** `cd tool/audit && dart test test/class_modifiers_test.dart` · Expected: FAIL
- [ ] **Step 3: Implementieren** (zeilenbasierter Regex, Zeilen mit führendem `//` ignorieren).
- [ ] **Step 4: Run** wie Step 2 · Expected: PASS
- [ ] **Step 5: `api_arch.sh`**
  - `dart pub global run dart_apitool extract --input packages/trooper --output docs/audit/raw/api_trooper.json` (analog für `trooper_bloc`)
  - `dart run tool/audit/bin/class_modifiers.dart packages/trooper/lib packages/trooper_bloc/lib` → `raw/class_modifiers.txt`
  - `dart pub global run lakos packages/trooper/lib --metrics -o docs/audit/raw/lakos_trooper.dot` (Exit ≠ 0 bei Zyklen; analog `trooper_bloc`)
  - `dart pub global run dart_code_linter:metrics analyze packages/trooper/lib --cyclomatic-complexity=15 --reporter=json` → `raw/metrics_trooper.json` (analog `trooper_bloc`)
  - Dateigrößen: `find packages/*/lib -name '*.dart' | xargs wc -l | sort -rn` → `raw/file_sizes.txt`
- [ ] **Step 6: Ausführen** Run: `bash tool/audit/scripts/api_arch.sh` · Expected: alle Rohdateien und `.exit` vorhanden.
- [ ] **Step 7: Kriterien eintragen**: ARCH-02, ARCH-03, QUAL-03. API-02 nur mit Rohnachweis, bewertet in Task 10.
  Hypothesen API-02 und ARCH-03 (Spec §5) bestätigen oder verwerfen.
- [ ] **Step 8: Commit** `git add tool/audit docs/audit && git commit -m "audit: api inventory and architecture metrics"`

---

### Task 6: Phase 1 – Release, Dokumentation, Sicherheit, Performance-Baseline

**Files:**
- Create: `tool/audit/scripts/release.sh`

- [ ] **Step 1: `release.sh`**
  - `run_step pana_trooper pana --no-warning --json packages/trooper` (analog `pana_bloc`; Score aus JSON nach `raw/pana_summary.txt`)
  - `run_step dryrun_trooper` mit `dart pub publish --dry-run` in `packages/trooper`; `run_step dryrun_bloc` mit `flutter pub publish --dry-run`
  - `run_step dartdoc_trooper` mit `dart doc --output ../../docs/audit/raw/dartdoc_trooper` (analog `trooper_bloc`)
  - `run_step osv osv-scanner --lockfile pubspec.lock` (fehlt das Tool: `brew install osv-scanner`)
  - `run_step bench_baseline` mit `dart run benchmark/trooper_benchmark.dart` in `packages/trooper`, dreimal; Median je Benchmark nach `raw/bench_baseline.txt`
  - Paketinhalt: Dateiliste aus der Dry-Run-Ausgabe, Dateien > 500 KB markieren → `raw/package_contents.txt`
- [ ] **Step 2: Ausführen** Run: `bash tool/audit/scripts/release.sh` · Expected: alle `.exit` vorhanden.
- [ ] **Step 3: Kriterien eintragen**: REL-01, REL-03, SEC-04 (OSV-Teil; `SECURITY.md`-Teil in Task 12), DOC-01
  (Dartdoc-Warnungen + `public_member_api_docs` aus Task 2), PERF-02 (Baseline vorhanden; CI fehlt → höchstens `partial`).
  Scheitert pana an der Workspace-Auflösung, als REL-01-Finding mit Fehlertext führen.
- [ ] **Step 4: Commit** `git add tool/audit docs/audit && git commit -m "audit: release, docs, security and perf baseline"`

---

### Task 7: Phase 2 – Nebenläufigkeit (ASYNC)

**Files:**
- Create: `packages/trooper/dart_test.yaml` (`tags: { audit: {} }`), `packages/trooper/test/audit/async_audit_test.dart`

**Interfaces:**
- Consumes: Core-API (`QueryTrooper`, `QueryTrooper.cancellable`, `KeyedQueryTrooper`, `TrooperMutation`,
  `TrooperMutationQueue.add<T>(Future<T> Function())`, `TrooperQueryQueue.activeCount`, `TrooperCancelToken`,
  `QueryConflictPolicy.values`, `TrooperConfig(deduplicate:, conflictPolicy:, timeToLive:, stalePolicy:)`).

Alle Tests mit `@Tags(['audit'])` am Dateianfang; Zeitsteuerung per `fakeAsync`, Reihenfolge per `Completer`.
Fehler in der Zone werden pro Test mit `runZonedGuarded` gesammelt; jeder Test prüft zusätzlich `zoneErrors` auf leer.

- [ ] **Step 1: Prüftests schreiben**

```dart
for (final policy in QueryConflictPolicy.values) {
  test('ASYNC-01 older response never overwrites newer (QueryTrooper, $policy)', () async {
    // fetch returns completers[i].future for call i; deduplicate: false
    // q.get((), forceRefresh: true) twice; complete completers[1] with 'new', then completers[0] with 'old'
    expect(q.currentData(), 'new');
    expect(q.cache.get<String>(const QueryKey('ns', ())), 'new');
  });
}
test('ASYNC-01 older response never overwrites newer (KeyedQueryTrooper)', ...);  // same with q['k']
test('ASYNC-03 failing SWR background revalidation is observable', ...);
  // stale entry in L1 (timeToLive elapsed via fakeAsync), stalePolicy keepStaleWhileRevalidate, fetch throws
  // expect: stream emits DataError with staleData == old value OR telemetry emits an error event; zoneErrors empty
test('ASYNC-04 listener may invalidate and dispose during notification', ...);
  // listener on stream: on first DataLoaded call q.invalidate(); await q.dispose(); expect zoneErrors empty
test('ASYNC-05 no state update after cancel', ...);
  // QueryTrooper.cancellable, conflictPolicy: cancel; get((t:'a')) then get((t:'b')); complete 'a' after 'b'
  // expect: no DataLoaded('a') in recorded states; TrooperMutation with cancelled token: currentState is not DataLoaded
test('ASYNC-06 mutation queue serializes in submission order', ...);
  // three queue.add tasks; record start order; completing task 0 must precede start of task 1
  // expect(startOrder, [0, 1, 2]); expect(endOrder, [0, 1, 2])
test('ASYNC-07 randomized interleavings keep last-issued result (1000 seeds)', ...);
  // per seed: fakeAsync; 20 random ops from {get, refresh, invalidate}; fetch returns its own sequence number
  // after a random latency 0–50 ms; after flushTimers: currentData == highest sequence number whose fetch
  // was issued after the last invalidate, and queryQueue.activeCount == 0
```

- [ ] **Step 2: ASYNC-02 charakterisieren**: Dartdoc von `invalidate`, `refresh`, `TrooperMutation.execute` lesen.
  Je Kombination (invalidate / refresh / mutation mit `invalidateOnSuccess` während eines laufenden `get`) einen Test
  `ASYNC-02 <combination>` schreiben, der das **dokumentierte** Verhalten prüft. Ist nichts dokumentiert, prüft der
  Test das beobachtete Verhalten; das Fehlen der Dokumentation wird als Finding geführt (ASYNC-02 und DOC-04).
- [ ] **Step 3: Rollback prüfen**: `TrooperMutationSideEffects` bietet nur `onStarted`, `onSuccess`, `onError`.
  Verspricht README/Dartdoc Optimistic Updates mit Rollback, ist das ein Finding (ASYNC-06 und FEAT-01); sonst
  ASYNC-06 nur nach der Reihenfolgegarantie bewerten.
- [ ] **Step 4: Run** `cd packages/trooper && dart test test/audit/async_audit_test.dart`
  Expected: Jeder Test liefert ein Ergebnis; rote Tests sind Findings.
- [ ] **Step 5: Findings anlegen** und rote Tests mit `skip: 'F-NNN'` versehen; ASYNC-01…07 bewerten; ASYNC-03 mit dem
  Lint-Ergebnis aus Task 2 kombinieren.
- [ ] **Step 6: Verifizieren** Run: `dart test test/audit && bash ../../tool/audit/scripts/guard.sh` · Expected: PASS (mit Skips), `GUARD: ok`
- [ ] **Step 7: Commit** `git add packages/trooper/dart_test.yaml packages/trooper/test/audit docs/audit && git commit -m "audit: concurrency probes"`

---

### Task 8: Phase 2 – Lifecycle und Ressourcen (LIFE)

**Files:**
- Create: `packages/trooper/test/audit/lifecycle_audit_test.dart`, `packages/trooper/benchmark/audit_soak.dart`,
  `packages/trooper_bloc/test/flutter_test_config.dart`, `packages/trooper_bloc/test/audit/bloc_audit_test.dart`
- Modify: `packages/trooper_bloc/pubspec.yaml` (Dev-Dependency `leak_tracker_flutter_testing`, neueste mit Flutter 3.47 kompatible Version)

- [ ] **Step 1: Prüftests Core**

```dart
// disposables(): one fresh instance each of QueryTrooper, KeyedQueryTrooper, LocalTrooper, KeyedLocalTrooper,
// StreamTrooper, KeyedStreamTrooper, TrooperMutation, LoadMore, CacheStore(evictionInterval: 1s),
// TrooperQueryQueue, TrooperMutationQueue and a TrooperController subclass using all factory methods
for (final (name, create) in disposables()) {
  test('LIFE-01 $name dispose is idempotent', () async {
    final x = create(); await x.dispose(); await x.dispose(); // no throw
  });
  test('LIFE-02 $name leaves no timers after dispose', () => fakeAsync((async) {
    final x = create(); /* trigger one operation */ x.dispose(); async.flushMicrotasks();
    expect(async.pendingTimers, isEmpty); expect(async.periodicTimerCount, 0);
  }));
}
test('LIFE-02 stream subscribers receive done after dispose', ...);   // onDone called for QueryTrooper.stream
test('LIFE-04 controller dispose cascades with in-flight request', ...);
  // controller.query with Completer fetch; start get; await controller.dispose(); complete completer
  // expect query.isDisposed; no state emitted after dispose; zoneErrors empty
```

Zusätzlich je Typ einen Test `LIFE-01 $name use after dispose`, der das dokumentierte Verhalten nach `dispose` prüft.
Ist es nicht dokumentiert, wird es charakterisiert und als Finding geführt.

- [ ] **Step 2: LIFE-03 per Review**: `CacheStore` sowie die Maps in den Keyed-Troopers und in `KeyedStatefulStream`
  auf Größengrenzen prüfen. Ergebnis mit `Datei:Zeile` festhalten. Hypothese LIFE-03 (Spec §5) bestätigen oder verwerfen.
- [ ] **Step 3: Soak-Test** `audit_soak.dart`: 10.000 Keys, 1.000.000 gemischte Operationen (get/set/invalidate) auf
  `KeyedLocalTrooper` und `KeyedQueryTrooper` (sofort auflösender Fetch). `ProcessInfo.currentRss` nach 100.000
  Operationen Warm-up und am Ende ausgeben. Run: `dart run benchmark/audit_soak.dart > ../../docs/audit/raw/soak.txt`.
  Bewertung: Endwert ≤ 105 % des Warm-up-Werts.
- [ ] **Step 4: Leak-Tracking in `trooper_bloc`**: `flutter_test_config.dart` mit `LeakTesting.enable()` und
  `LeakTesting.settings = LeakTesting.settings.withIgnoredAll()` nur für Flutter-interne Klassen, falls nötig.
  `bloc_audit_test.dart`: `Tubit` und `Tloc` mit `FakeAccessor` erzeugen, `close()` zweimal aufrufen, danach
  `FakeAccessor`-Stream ohne Listener (Test `LIFE-02 Tubit close cancels source subscriptions`).
  Run: `cd packages/trooper_bloc && flutter test` · Expected: Leak-Meldungen erscheinen in der Ausgabe oder nicht; beides
  wird als Nachweis notiert.
- [ ] **Step 5: Run** `cd packages/trooper && dart test test/audit/lifecycle_audit_test.dart`
- [ ] **Step 6: Findings anlegen**, rote Tests mit `skip` versehen, LIFE-01…05 bewerten.
- [ ] **Step 7: Verifizieren** `bash tool/audit/scripts/guard.sh` · Expected: `GUARD: ok`
- [ ] **Step 8: Commit** `git add packages docs/audit && git commit -m "audit: lifecycle and resource probes"`

---

### Task 9: Phase 2 – Fehlerbehandlung und Datensicherheit (ERR, SEC-01…03)

**Files:**
- Create: `packages/trooper/test/audit/error_audit_test.dart`, `docs/audit/raw/catch_sites.md`

- [ ] **Step 1: Prüftests**

```dart
test('ERR-03 exponential retry timing', () => fakeAsync((async) {
  // RetryPolicy.exponential(maxRetries: 3, initialDelay: 100ms, backoffMultiplier: 2); fetch always throws;
  // record async.elapsed at each fetch call
  expect(callTimesMs, [0, 100, 300, 700]);
}));
test('ERR-03 maxDelay clamps backoff', ...);          // maxDelay: 250ms → [0, 100, 300, 550]
test('ERR-03 retryWhen false stops after first call', ...);   // expect(calls, 1)
for (final (label, raw) in [
  ('missing version', '{"payload":"\\"x\\"","createdAt":"2026-01-01T00:00:00.000"}'),
  ('future version', '{"version":999,"payload":"\\"x\\"","createdAt":"2026-01-01T00:00:00.000"}'),
  ('not json', 'not json'),
  ('wrong payload type', /* valid envelope whose payload the codec cannot decode */),
]) {
  test('ERR-04/SEC-03 corrupt L2 entry ($label) falls back to fetch', () async {
    // InMemoryStorageBackend pre-filled under key.storageKey; QueryTrooper with codec + storage, empty L1
    expect(await q.get(()), 'fresh'); expect(api.callCount, 1);
    expect(StorageEnvelope.tryDecode((await storage.read(key))!)?.version, StorageEnvelope.currentVersion);
  });
}
test('SEC-02 default logger does not print payloads', ...);
  // ConsoleTrooperLogger() attached to a TelemetryHub; run query returning 'secret-123' inside a Zone
  // with ZoneSpecification(print: ...) capturing output; expect(output.join(), isNot(contains('secret-123')))
```

- [ ] **Step 2: ERR-02-Inventar**: alle `catch`- und `.ignore()`-Stellen in `packages/*/lib` per `grep -rn` auflisten
  (Vorab-Zählung: 139). In `raw/catch_sites.md` je Stelle klassifizieren: `rethrow` · `→ State` · `→ Telemetrie` ·
  `verschluckt`. Jede verschluckte Stelle ist ein Finding; gleichartige Stellen in einem Modul werden zu einem Finding
  zusammengefasst.
- [ ] **Step 3: Review ERR-01, ERR-05, SEC-01**: Prüfen, ob die `TrooperException`-Hierarchie Fehler aus Fetch und
  Codec unterscheidbar macht (vorhanden sind Cancelled, Timeout, Storage). Alle `throw`-Stellen auf handlungsleitende
  Meldungen durchsehen. Klären, ob die L2-Klartext-Speicherung dokumentiert ist und ob ein Verschlüsselungs-Hook
  (Codec/Backend) existiert.
- [ ] **Step 4: Run** `cd packages/trooper && dart test test/audit/error_audit_test.dart`
- [ ] **Step 5: Findings anlegen**, `skip` setzen, ERR-01…05 und SEC-01…03 bewerten. Hypothese ERR-04 (Spec §5)
  bestätigen oder verwerfen.
- [ ] **Step 6: Verifizieren und committen** `bash tool/audit/scripts/guard.sh && git add packages docs/audit && git commit -m "audit: error handling and data safety probes"`

---

### Task 10: Phase 2 – Public API (API, OBS)

**Files:**
- Create: `docs/audit/api-inventory.md`

- [ ] **Step 1: Inventar**: aus `raw/api_*.json` je exportiertem Symbol eine Zeile: Symbol · Art · Datei ·
  Entscheidung (`behalten` / `intern machen` / `umbenennen` / `entfernen`) · Begründung · freeze-relevant.
  Zusätzliche Spalte „Modifier-Vorschlag“ für die Klassen aus `raw/class_modifiers.txt`.
- [ ] **Step 2: Gezielt bewerten** (je Punkt Entscheidung im Inventar, Finding bei Handlungsbedarf):
  - `TrooperController.executeOrder66()` neben `clearAll()` (Alias-API ohne fachlichen Namen)
  - veränderliche globale Defaults `Trooper.setDefaultConfig`, `TrooperConfig.defaultConfig`, `TrooperConfig.setDefaultConfig`
  - doppelter Getter `TrooperConfig.queryConflictPolicy` ↔ `conflictPolicy`
  - `typedef Parameter = Record` in `lib/types/` außerhalb von `src/`
  - Re-Exporte in `trooper_bloc.dart`: komplettes `trooper`, `Emitter` aus `flutter_bloc`, `FutureOr` aus `dart:async` (API-06)
  - `@protected`-Member und `_Bound*Accessor`-Muster: stabil genug für den Freeze?
  - Symmetrie der Paare Query/KeyedQuery, Local/KeyedLocal, Stream/KeyedStream (Methodennamen, Parameter, Rückgaben) (API-03)
  - `dynamic` in öffentlichen Signaturen (API-07); `DataLoaded` ist `base`, alle anderen State-Klassen `final`: beabsichtigt?
  - Telemetrie-Events in `trooper_event.dart`: dokumentiert und als stabil markiert? (OBS-01); Log-Level im Logger (OBS-02)
- [ ] **Step 3: API-04, API-05 prüfen**: Gibt es eine Deprecation-Policy im Repo? Gibt es eine API-Baseline? Beides
  fehlt voraussichtlich (keine `@Deprecated`-Annotation, keine CI).
- [ ] **Step 4: Kriterien eintragen**: API-01…07, OBS-01…03. Hypothesen API-02 und API-06 (Spec §5) bestätigen oder
  verwerfen. Jedes freeze-relevante Finding mindestens P1 (Spec 2.3).
- [ ] **Step 5: Commit** `git add docs/audit && git commit -m "audit: public API review"`

---

### Task 11: Phase 2 – Architektur, Testqualität, Performance

**Files:**
- Create: `packages/trooper/test/audit/storage_contract_probe_test.dart` (nur falls Step 2 ein Test-Kit findet)

- [ ] **Step 1: ARCH-04**: Keyed- und Non-Keyed-Varianten gegenüberstellen (`query_trooper.dart` ↔ `keyed_query_trooper.dart`,
  `local_trooper.dart` ↔ `keyed_local_trooper.dart`, `stream_trooper.dart` ↔ `keyed_stream_trooper.dart`).
  Duplizierte Logikblöcke mit Zeilenbereichen festhalten. Ergebnis: Konsolidierungsempfehlung oder Begründung.
- [ ] **Step 2: ARCH-05**: Verträge von `StorageBackend`, `TrooperCodec`, `TrooperLogger` (Dartdoc: Fehlerverhalten,
  Nebenläufigkeit, Rückgabewerte von `delete`/`read`) prüfen. Gibt es ein exportiertes Contract-Test-Kit?
  `InMemoryStorageBackend` dient als Referenzimplementierung.
- [ ] **Step 3: ARCH-06**: Gibt es ADRs im Repo?
- [ ] **Step 4: TEST-04, TEST-05**: Prüfen, ob `trooper_bloc/lib/testing.dart` (`FakeAccessor`) durch
  `test/testing_test.dart` vollständig abgedeckt ist (Coverage aus Task 3). Bedarf für Core-Test-Helfer beurteilen
  (z. B. Fake-Trooper für Nutzer ohne BLoC). Gibt es Property-Based-Tests?
- [ ] **Step 5: PERF-01, PERF-03**: `benchmark/trooper_benchmark.dart` gegen die fünf Hot Paths aus PERF-01 abgleichen.
  Komplexität der Keyed-Operationen aus dem Code ableiten (Map-Zugriffe, Iterationen über alle Keys bei
  `invalidate`/`removeWhere`). Telemetrie-Overhead: Benchmark „Cache-Hit“ mit und ohne Listener am `TelemetryHub`
  vergleichen (Schwelle < 2 %).
- [ ] **Step 6: Kriterien eintragen**: ARCH-04…06, TEST-04, TEST-05, PERF-01, PERF-03; Findings anlegen.
- [ ] **Step 7: Commit** `git add packages docs/audit && git commit -m "audit: architecture, test quality, performance review"`

---

### Task 12: Phase 2/3 – Dokumentation, Release, Governance, Kompatibilität, Traceability

**Files:**
- Create: `docs/audit/traceability.md`, `packages/trooper/test/audit/feature_audit_test.dart`,
  `packages/trooper_bloc/test/audit/bloc_feature_audit_test.dart`

- [ ] **Step 1: Feature-Inventar (FEAT-01)**: Claims aus `README.md` (Root), `packages/*/README.md`, `packages/*/CHANGELOG.md`,
  `CHANGELOG.md` (Root), `packages/*/skills/*/SKILL.md` und den Bibliotheks-Dartdocs sammeln. `traceability.md` mit
  den Spalten: ID (`C-NNN`) · Claim · Quelle (`Datei:Zeile`) · belegender Test (`Datei:Testname`) · Status
  (`belegt` / `teilweise` / `fehlt`).
- [ ] **Step 2: Fehlende Belege als Prüftests**: für FEAT-02 (Zustandsfolge bei SWR für Query, KeyedQuery und Stream:
  kein Zustand ohne Daten zwischen zwei `DataLoaded`), FEAT-03 (Coalescing mit N = 2 und N = 50, auch über zwei
  Controller mit geteilter `TrooperQueryQueue`), FEAT-04 (je Wert von `StalePolicy`, `QueryConflictPolicy` und je
  `RetryPolicy`-Konstruktor ein Test, falls in Task 3 nicht vorhanden), FEAT-05 (Kaltstart aus L2, Write-through,
  Invalidierung beider Ebenen) und FEAT-06 (zwei gleichzeitige Updates von `FakeAccessor`s im selben Event-Loop
  ergeben genau eine Transition im `Tubit`; `Watched.state` liefert während `matchSources` einen konsistenten Snapshot).
  Run: `dart test test/audit/feature_audit_test.dart` bzw. `flutter test test/audit/bloc_feature_audit_test.dart`.
- [ ] **Step 3: FEAT-07, DOC-06**: Snippets aus den READMEs und `SKILL.md` in temporäre Dateien unter `docs/audit/raw/snippets/`
  extrahieren, mit passenden Imports versehen und `dart analyze` laufen lassen. Fehler je Snippet notieren.
- [ ] **Step 4: DOC-02…05**: README-Prüfung (Badges, Links, SDK-Angaben, Tooling-Claims; Linkcheck aller URLs per
  `curl -sI`). Vorhandensein von Getting Started, Konzepten, Rezepten, FAQ, Garantie-Abschnitt, Migrationsleitfaden und
  Keep-a-Changelog-Format prüfen. Hypothesen DOC-02 (Spec §5) bestätigen oder verwerfen.
- [ ] **Step 5: COMPAT-03, COMPAT-04**: Flutter-Untergrenze gegen Dart-Untergrenze abgleichen (Flutter 3.24 bringt
  Dart 3.5). Isolate-Verhalten: Ist dokumentiert, dass `CacheStore` und `TrooperQueryQueue` pro Isolate gelten?
- [ ] **Step 6: REL-02, REL-04, GOV-01…04, SEC-04 (Teil `SECURITY.md`)**: Versionsstrategie (zwei Packages mit
  unterschiedlichen Versionen, `trooper_bloc` hängt an `trooper: ^0.1.0-beta.1`), Publisher, `.github/` (Workflows,
  Templates, Dependabot), CONTRIBUTING, CODE_OF_CONDUCT, Support-Policy. Branch-Protection per
  `gh api repos/ParceApp/trooper/branches/main/protection` (Fehler 404 = nicht aktiv).
- [ ] **Step 7: Kriterien eintragen**: FEAT-01…07, DOC-02…06, COMPAT-03/04, REL-02/04, GOV-01…04, SEC-04 (vervollständigt).
  MARKET-01 auf `na` mit `note: optional, nicht beauftragt`, sofern du die Marktanalyse nicht ausdrücklich beauftragst.
- [ ] **Step 8: Verifizieren und committen** `bash tool/audit/scripts/guard.sh && git add packages docs/audit && git commit -m "audit: docs, release, governance and feature traceability"`

---

### Task 13: Phase 4 – Bewertung und Report

**Files:**
- Create: `docs/audit/REPORT.md`, `docs/audit/score.md`
- Modify: `docs/audit/criteria.yaml`, `docs/audit/findings.md`

- [ ] **Step 1: Vollständigkeit prüfen**
  - `for f in docs/audit/raw/*.exit; do echo "$f $(cat $f)"; done` → jeder Exit ≠ 0 ist in einem Kriterium oder Finding erklärt
  - `grep -rn "Future.*delayed" packages/*/test/audit` → jeder Treffer liegt innerhalb von `fakeAsync`
  - `grep -rn "skip: 'F-" packages/*/test/audit` → jede referenzierte ID existiert in `findings.md`
  - `bash tool/audit/scripts/guard.sh` → `GUARD: ok`
- [ ] **Step 2: Scorer ausführen** Run: `dart run tool/audit/bin/score.dart docs/audit/criteria.yaml --out docs/audit/score.md`
  Expected: Exit 0 oder 1, niemals 2 (keine unbewerteten Kriterien).
- [ ] **Step 3: Findings konsolidieren**: Duplikate zusammenführen, Schweregrade nach Spec 2.3 prüfen (jedes
  freeze-relevante Finding ≥ P1), Aufwand S/M/L ergänzen, nach Schwere sortieren.
- [ ] **Step 4: `REPORT.md` schreiben**: Geprüfter Commit und Tool-Versionen; Gate-Status mit allen Gründen;
  Reifegrad-Tabelle der 16 Dimensionen und Gesamtscore (aus `score.md`); Top-10-Findings; Status der Hypothesen
  aus Spec §5 (bestätigt/verworfen); Empfehlung für den Weg zu 1.0, gruppiert nach „vor dem API-Freeze“ und
  „danach möglich“; Abschnitt „Tooling“ mit Grenzen des Audits (z. B. Mutation-Stichprobe, RSS-Messung).
- [ ] **Step 5: Commit** `git add docs/audit && git commit -m "audit: scoring, findings and report"`

---

## Parallelisierung (Spec 4.7)

Task 1 muss zuerst laufen. Danach sind die Tasks 2–6 voneinander unabhängig, ebenso die Tasks 7–12, mit einer
Einschränkung: Alle schreiben in `criteria.yaml` und `findings.md`. Wer parallel arbeitet, vergibt Finding-IDs pro
Task aus einem eigenen Bereich (Task 7: F-100…, Task 8: F-200…, usw.) und führt die Einträge in Task 13 zusammen.
Standard ist sequenziell.
