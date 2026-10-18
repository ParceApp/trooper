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
