import 'catalog.dart';

const _priorityWeight = {Priority.must: 3, Priority.should: 2, Priority.could: 1};
const _statusValue = {Status.met: 1.0, Status.partial: 0.5, Status.notMet: 0.0};

/// Weighted share of fulfilled criteria (0..1); `null` if nothing is scorable.
double? dimensionScore(Dimension d) {
  var sum = 0.0;
  var weights = 0;
  for (final c in d.criteria) {
    final value = _statusValue[c.status];
    if (value == null) continue; // na or not assessed
    final w = _priorityWeight[c.priority]!;
    sum += w * value;
    weights += w;
  }
  return weights == 0 ? null : sum / weights;
}

/// Maturity 0–3 as defined in spec section 2.2.
int maturity(Dimension d) {
  final musts = d.criteria.where((c) => c.priority == Priority.must);
  final mustsMetOrNa =
      musts.every((c) => c.status == Status.met || c.status == Status.na);
  final metMustsAutomated = musts
      .where((c) => c.status == Status.met)
      .every((c) => c.automatedInCi);
  if (mustsMetOrNa && metMustsAutomated) return 3;
  if (musts.every((c) =>
      c.status == Status.met ||
      c.status == Status.partial ||
      c.status == Status.na)) {
    return 2;
  }
  if (d.criteria
      .any((c) => c.status == Status.met || c.status == Status.partial)) {
    return 1;
  }
  return 0;
}

/// Mean of dimension scores weighted by [Dimension.weight].
double? totalScore(Catalog c) {
  var sum = 0.0;
  var weights = 0;
  for (final d in c.dimensions) {
    final s = dimensionScore(d);
    if (s == null) continue;
    sum += d.weight * s;
    weights += d.weight;
  }
  return weights == 0 ? null : sum / weights;
}

class GateResult {
  GateResult({
    required this.passed,
    required this.reasons,
    required this.pending,
  });

  final bool passed;
  final List<String> reasons;
  final List<String> pending;
}

/// 1.0 release gate as defined in spec section 2.5.
GateResult evaluateGate(Catalog c) {
  final reasons = <String>[];
  final pending = <String>[];
  for (final d in c.dimensions) {
    for (final cr in d.criteria) {
      if (cr.status == null) {
        pending.add(cr.id);
      } else if (cr.priority == Priority.must &&
          cr.status != Status.met &&
          cr.status != Status.na) {
        reasons.add('${cr.id}: must criterion is ${cr.status!.name}');
      }
    }
    final min = d.gateMinMaturity;
    if (min != null) {
      final m = maturity(d);
      if (m < min) reasons.add('${d.id}: maturity $m below gate minimum $min');
    }
  }
  for (final f in c.findings) {
    if (f.open && (f.severity == Severity.p0 || f.severity == Severity.p1)) {
      reasons.add('${f.id}: open ${f.severity.name.toUpperCase()} finding');
    }
  }
  return GateResult(
    passed: reasons.isEmpty && pending.isEmpty,
    reasons: reasons,
    pending: pending,
  );
}
