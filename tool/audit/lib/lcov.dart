class CoverageSummary {
  CoverageSummary({
    required this.lineHit,
    required this.lineFound,
    required this.branchHit,
    required this.branchFound,
  });

  final int lineHit;
  final int lineFound;
  final int branchHit;
  final int branchFound;

  double get linePct => lineFound == 0 ? 0 : 100 * lineHit / lineFound;
  double? get branchPct =>
      branchFound == 0 ? null : 100 * branchHit / branchFound;
}

/// Counts `DA` and `BRDA` records (not `LF`/`LH`, which tools emit
/// inconsistently). A `BRDA` count of `-` means the branch was never reached.
CoverageSummary summarizeLcov(String lcov) {
  var lineHit = 0, lineFound = 0, branchHit = 0, branchFound = 0;
  for (final line in lcov.split('\n')) {
    if (line.startsWith('DA:')) {
      lineFound++;
      final hits = int.tryParse(line.substring(3).split(',')[1]) ?? 0;
      if (hits > 0) lineHit++;
    } else if (line.startsWith('BRDA:')) {
      branchFound++;
      final taken = line.substring(5).split(',')[3];
      if (taken != '-' && (int.tryParse(taken) ?? 0) > 0) branchHit++;
    }
  }
  return CoverageSummary(
    lineHit: lineHit,
    lineFound: lineFound,
    branchHit: branchHit,
    branchFound: branchFound,
  );
}
