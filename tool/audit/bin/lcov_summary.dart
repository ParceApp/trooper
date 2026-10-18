import 'dart:io';

import 'package:trooper_audit_tool/lcov.dart';

/// Usage: dart run bin/lcov_summary.dart <lcov.info>
void main(List<String> args) {
  final s = summarizeLcov(File(args.single).readAsStringSync());
  stdout
    ..writeln('lines: ${s.linePct.toStringAsFixed(1)}% '
        '(${s.lineHit}/${s.lineFound})')
    ..writeln(s.branchPct == null
        ? 'branches: n/a'
        : 'branches: ${s.branchPct!.toStringAsFixed(1)}% '
            '(${s.branchHit}/${s.branchFound})');
}
