import 'dart:io';

import 'package:trooper_audit_tool/catalog.dart';
import 'package:trooper_audit_tool/scoring.dart';

/// Usage: `dart run bin/score.dart <criteria.yaml> [--out <file.md>]`
///
/// Exit codes: 0 gate passed, 1 gate failed, 2 unassessed criteria remain,
/// 64 usage error.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: score.dart <criteria.yaml> [--out <file.md>]');
    exit(64);
  }
  final outIndex = args.indexOf('--out');
  final out = outIndex >= 0 && outIndex + 1 < args.length
      ? args[outIndex + 1]
      : null;

  final catalog = parseCatalog(File(args.first).readAsStringSync());
  final gate = evaluateGate(catalog);
  final report = _render(catalog, gate);

  stdout.write(report);
  if (out != null) File(out).writeAsStringSync(report);

  exit(gate.pending.isNotEmpty ? 2 : (gate.passed ? 0 : 1));
}

String _pct(double? v) => v == null ? 'n/a' : '${(v * 100).toStringAsFixed(1)} %';

String _render(Catalog catalog, GateResult gate) {
  final b = StringBuffer()
    ..writeln('# Audit Score')
    ..writeln()
    ..writeln('Audited commit: `${catalog.meta['audited_commit']}`')
    ..writeln()
    ..writeln('| Dimension | Weight | Score | Maturity | Gate minimum |')
    ..writeln('|---|---|---|---|---|');
  for (final d in catalog.dimensions) {
    b.writeln('| ${d.id} | ${d.weight} | ${_pct(dimensionScore(d))} | '
        '${maturity(d)} | ${d.gateMinMaturity ?? '–'} |');
  }
  b
    ..writeln()
    ..writeln('**Total score:** ${_pct(totalScore(catalog))}')
    ..writeln()
    ..writeln('**Gate:** ${gate.passed ? 'PASSED' : 'NOT PASSED'}');
  if (gate.reasons.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Reasons:')
      ..writeln();
    for (final r in gate.reasons) {
      b.writeln('- $r');
    }
  }
  if (gate.pending.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Not yet assessed (${gate.pending.length}): '
          '${gate.pending.join(', ')}');
  }
  return b.toString();
}
