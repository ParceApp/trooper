# Enterprise-Readiness-Audit: `trooper` und `trooper_bloc`

| | |
|---|---|
| **Geprüfter Stand** | `main` @ `222815e` („fix query trooper test“) |
| **Pakete** | `trooper` 0.1.0-beta.1, `trooper_bloc` 0.1.2-beta.1 |
| **Ziel** | 1.0.0 auf pub.dev mit eingefrorener Public API |
| **Prüfrahmen** | `docs/superpowers/specs/2026-10-18-enterprise-readiness-audit-design.md` |
| **Werkzeuge** | Dart 3.13.5, Flutter 3.47.6, pana 0.23.19, dart_apitool 0.23.2, lakos 2.0.7, dart_code_linter 4.4.2, mutation_test 1.8.1, coverage 1.16.0, osv-scanner 2.7.0 |
| **Datum** | 2026-10-18 |

## Ergebnis

**Gate für 1.0: nicht bestanden.** Gesamtscore **@@SCORE@@**. 58 Findings: 1 × P0, 30 × P1, 22 × P2, 5 × P3; 10 davon
sind freeze-relevant, also nach dem API-Freeze nur noch per Major-Release behebbar.

Der Kern ist solide gebaut: Request-Coalescing, Zero-Flicker-SWR, FIFO-Mutationen, Snapshot-Locking und
Microtask-Batching funktionieren wie beschrieben, alle Suiten laufen 100-mal flake-frei, auf VM, dart2js und dart2wasm
grün, ohne bekannte Schwachstellen in den Abhängigkeiten, und `trooper` erreicht bei pana 160/160. Für ein 1.0 fehlen
drei Dinge:

1. **Korrektheit unter Nebenläufigkeit und Lifecycle.** Ein P0 (`parallel` überschreibt neuere mit älteren Daten,
   entgegen der Dartdoc) und mehrere P1: `invalidate()`/`clearAll()` lassen persistierte Nutzerdaten auf der Platte,
   `forward` liefert überholte Ergebnisse aus, Mutationen ignorieren den Abbruch, `KeyedStreamTrooper.dispose()` kann
   abbrechen.
2. **Eine einfrierbare API.** 38 Klassen ohne Modifier, sechs exportierte Implementierungsdetails, zwei `sealed`
   Hierarchien, die nicht wachsen dürfen, und neun Extensions mit 51 Membern, die niemand normal aufrufen kann.
3. **Absicherung und Vertrag.** Keine CI, Coverage 83,7 % statt 95 %, keine dokumentierten Garantien, und mehrere
   Doku- und Skill-Beispiele kompilieren nicht.

## Gate-Prüfung

| Bedingung (Spec 2.5) | Status |
|---|---|
| Alle Must-Kriterien erfüllt | nein: @@MUST@@ |
| Keine offenen P0/P1-Findings | nein: 1 × P0, 30 × P1 |
| Reifegrad ≥ 2 überall, API/ASYNC/LIFE/ERR/COMPAT = 3 | nein: ohne CI erreicht keine Dimension Reifegrad 3 |
| Harte Schwellen | siehe Tabelle |

| Schwelle | Soll | Ist |
|---|---|---|
| pana | 160/160 | `trooper` 160/160; `trooper_bloc` 45/160 (nicht auswertbar, solange `trooper` unveröffentlicht ist) |
| Dry-Run | 0 Warnungen | `trooper` 0; `trooper_bloc` 1 (CHANGELOG) |
| Analyzer (VGA + strict) | 0 | 970 Issues (614 in `lib/`, alle INFO) |
| Dartdoc | 100 % | 41 öffentliche Member ohne Doku, 27 kaputte Referenzen |
| Line-Coverage | ≥ 95 % / ≥ 90 % | `trooper` 83,7 %; `trooper_bloc` 99,2 % |
| Branch-Coverage `trooper` | ≥ 85 % | 78,9 % |
| Mutation-Score | ≥ 75 % | @@MUTATION@@ |
| Flakiness | 100 Läufe ohne Fehler | erfüllt (beide Pakete 100/100) |
| CI-Matrix | grün | keine CI; lokal: VM, dart2js, dart2wasm grün; Min-SDK ungetestet |
| API-Diff | in CI | fehlt |
| Benchmarks | Baseline + 10 %-Schranke | Baseline erstellt; Streuung bis 70 %, keine CI |

## Reifegrad und Score

@@SCORETABLE@@

Gewichtung: ASYNC, LIFE, ERR und API zählen doppelt. Der Score zeigt den Fortschritt, über die Freigabe entscheidet
nur das Gate.

## Top 10 Findings

| # | Finding | Schwere | freeze | Kurzbeschreibung |
|---|---|---|---|---|
| 1 | F-012 | P0 | nein | `QueryConflictPolicy.parallel`: ältere Antwort überschreibt neuere in Stream, Cache und L2; die versprochene Sequence-ID existiert nicht |
| 2 | F-014 | P1 | nein | `invalidate()` und `clearAll()` löschen L2 nicht; Logout hinterlässt Nutzerdaten, die der nächste Nutzer sieht |
| 3 | F-044 | P1 | ja | Alle 51 Member der `Parameterless*`-Extensions sind durch Instanzmethoden verdeckt; `accessor.get()` kompiliert nicht |
| 4 | F-013 | P1 | nein | Default-Policy `forward`: der überholte Aufrufer bekommt das alte Ergebnis, kurzzeitig auch im Stream |
| 5 | F-017 | P1 | nein | `KeyedStreamTrooper.dispose()` bricht mit `ConcurrentModificationError` ab und gibt Ressourcen nicht frei |
| 6 | F-016 | P1 | ja | Verhalten nach `dispose` undokumentiert und uneinheitlich; `KeyedStreamTrooper.getKey` hängt für immer |
| 7 | F-024 | P1 | nein | L2-Envelope-Version wird nie geprüft; Daten unbekannter Formatversionen werden ungeprüft ausgeliefert |
| 8 | F-020 | P1 | nein | Fehler in Nutzer-Callbacks (Side-Effects, Cancel-Listener) werden spurlos verschluckt |
| 9 | F-029 | P1 | ja | 38 öffentliche Klassen ohne `final`/`base`/`interface`/`sealed` |
| 10 | F-054 | P1 | nein | Keine CI; keine Schwelle wird automatisch geprüft |

Alle Findings mit Ort, Nachweis und Empfehlung: `docs/audit/findings.md`. Maschinenlesbar: `docs/audit/criteria.yaml`.

## Hypothesen aus der Vorab-Sichtung (Spec §5)

| Kriterium | Hypothese | Ergebnis |
|---|---|---|
| LIFE-03 | `CacheStore` nur mit TTL-Eviction, ohne Größengrenze | bestätigt (F-019), dazu unbegrenzte Per-Key-Maps |
| ERR-04 | Eintrag ohne `version` wird als `currentVersion` gelesen | bestätigt (F-024), ebenso Einträge mit unbekannter Version |
| API-02 | 46 Klassen ohne Modifier | bestätigt mit korrigierter Zahl: 38 öffentliche Klassen (F-029) |
| API-06 | `trooper_bloc` re-exportiert `trooper` und `Emitter` vollständig | bestätigt (F-033), zusätzlich `FutureOr` |
| QUAL-01, DOC-02 | `lints/recommended` statt `very_good_analysis` | bestätigt (F-001, F-045) |
| COMPAT-03 | `flutter: >=3.24.0` widerspricht `sdk: ^3.12.0` | bestätigt (F-050) |
| DOC-02 | Badge „Dart 3.5+“, lokale Links | bestätigt (F-045), dazu fehlendes GIF, kaputter Anker, nicht existierendes Paket |
| GOV-01 | keine CI | bestätigt (F-054) |
| ARCH-03 | Controller und `KeyedStreamTrooper` über 800 Zeilen | bestätigt (F-007), insgesamt fünf Dateien über 500 Zeilen |

## Empfehlung: Weg zu 1.0

**Vor dem API-Freeze** (alle freeze-relevanten Findings und die Korrektheits-P0/P1):

1. Korrektheit: F-012, F-013, F-014, F-015, F-017, F-024. Die zugehörigen Prüftests unter `packages/*/test/audit/`
   sind bereits geschrieben und mit `skip: 'F-NNN'` markiert; sie werden mit dem Fix zu Regressionstests.
2. API einfrierbar machen: F-028 (Interna), F-029 (Modifier), F-030 (Redundanzen), F-044 (Parameterless), F-033
   (Re-Exporte), F-022/F-035 (`sealed`), F-034, F-038 (Storage-Vertrag), F-016 (Verhalten nach `dispose`).
   Entscheidungen je Symbol stehen in `docs/audit/api-inventory.md`.
3. Vertrag schreiben: Garantien (F-048), Deprecation-Policy (F-031), Versionsstrategie (F-052).

**Infrastruktur für 1.0** (parallel zu 1. und 2.):

4. CI mit den Skripten aus `tool/audit/scripts/` (F-054): Analyzer mit VGA (F-001), Coverage-Schwellen (F-003),
   SDK-/Web-Matrix (F-005), API-Diff (F-032), Snippet- und Linkcheck (F-043, F-045), OSV (F-058).
5. Doku und Release: F-002, F-009, F-010, F-043, F-045, F-049, F-050.

**Danach in 1.x möglich:** die übrigen P2/P3-Findings (u. a. Duplikation F-037, Komplexität F-008, Jitter F-023,
Benchmarks F-011/F-041, Governance-Dateien F-055–F-057).

## Grenzen dieses Audits

- **Min-SDK:** Dart 3.12 ist lokal nicht installiert; die SDK-Untergrenze ist ungetestet (F-005).
- **Mutation-Testing:** @@MUTATIONNOTE@@
- **Speicher:** Der Soak-Test misst RSS, nicht den Dart-Heap; eine Garbage Collection lässt sich nicht erzwingen.
  Das Ergebnis (98 % des Warm-up-Werts) ist ein Indiz, kein Beweis für Leckfreiheit.
- **Leak-Tracking:** `leak_tracker` instrumentiert nur Flutter-Disposables, nicht die Trooper-Typen; dafür gibt es
  eigene Prüftests (LIFE-01/02).
- **F-017** ist nur unter `fakeAsync` deterministisch reproduzierbar; mit Echtzeit hängt der Fehler vom Timing ab.
- **pana für `trooper_bloc`** ist erst nach dem Release von `trooper` aussagekräftig.
- Die Prüftests prüfen die Garantien, die Doku und Dartdoc versprechen, oder bei fehlender Doku eine plausible
  Erwartung. Wo die Erwartung strittig ist (z. B. `StateError` nach `dispose`), steht das im Finding.

## Artefakte

| Datei | Inhalt |
|---|---|
| `docs/audit/criteria.yaml` | 74 Kriterien mit Status und Nachweis, 58 Findings |
| `docs/audit/findings.md` | alle Findings im Format der Spec 6.2 |
| `docs/audit/traceability.md` | 30 Feature-Claims mit Beleg |
| `docs/audit/api-inventory.md` | Entscheidung je exportiertem Symbol |
| `docs/audit/score.md` | Ausgabe von `tool/audit/bin/score.dart` |
| `packages/trooper/test/audit/`, `packages/trooper_bloc/test/audit/` | Prüftests (Tag `audit`) |
| `tool/audit/` | Scorer, Hilfsprogramme und Skripte zum Wiederholen des Audits |
