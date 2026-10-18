import 'dart:io';

import 'package:test/test.dart';
import 'package:trooper_audit_tool/catalog.dart';
import 'package:trooper_audit_tool/scoring.dart';

Criterion c(String id, Priority p, Status? s, {bool ci = false}) =>
    Criterion(id: id, priority: p, status: s, automatedInCi: ci);

Dimension dim(
  String id,
  List<Criterion> cs, {
  int weight = 1,
  int? gate = 2,
}) =>
    Dimension(id: id, weight: weight, gateMinMaturity: gate, criteria: cs);

Finding f(String id, Severity s, {bool open = true}) => Finding(
      id: id,
      severity: s,
      criterion: 'ASYNC-01',
      freezeRelevant: false,
      open: open,
    );

/// Every dimension's must criteria met and automated, no findings.
Catalog fullyMet({
  List<Finding> findings = const [],
  Map<String, Status?> override = const {},
  Set<String> notAutomated = const {},
}) {
  Criterion m(String id) => c(
        id,
        Priority.must,
        override.containsKey(id) ? override[id] : Status.met,
        ci: !notAutomated.contains(id),
      );
  return Catalog(
    meta: const {},
    findings: findings,
    dimensions: [
      dim('ASYNC', [m('ASYNC-01')], weight: 2, gate: 3),
      dim('API', [m('API-03')], weight: 2, gate: 3),
      dim('COMPAT', [m('COMPAT-01')], gate: 3),
      dim('FEAT', [m('FEAT-01')]),
      dim('MARKET', [c('MARKET-01', Priority.could, Status.notMet)], gate: null),
    ],
  );
}

void main() {
  test('dimensionScore weights priorities and halves partial', () {
    final d = dim('X', [
      c('X-01', Priority.must, Status.met),
      c('X-02', Priority.should, Status.partial),
      c('X-03', Priority.could, Status.notMet),
      c('X-04', Priority.must, Status.na),
    ]);
    expect(dimensionScore(d), closeTo(4 / 6, 1e-9));
  });

  test('dimensionScore is null when all criteria are na', () {
    expect(dimensionScore(dim('X', [c('X-01', Priority.must, Status.na)])),
        isNull);
  });

  test('maturity levels', () {
    expect(maturity(dim('X', [c('X-01', Priority.must, Status.met, ci: true)])),
        3);
    expect(maturity(dim('X', [c('X-01', Priority.must, Status.met)])), 2);
    expect(
        maturity(
            dim('X', [c('X-01', Priority.must, Status.partial, ci: true)])),
        2);
    expect(
        maturity(dim('X', [
          c('X-01', Priority.must, Status.notMet),
          c('X-02', Priority.should, Status.met),
        ])),
        1);
    expect(maturity(dim('X', [c('X-01', Priority.must, Status.notMet)])), 0);
  });

  test('totalScore weights dimensions', () {
    final cat = Catalog(meta: const {}, findings: const [], dimensions: [
      dim('ASYNC', [c('A-01', Priority.must, Status.partial)], weight: 2),
      dim('FEAT', [c('F-01', Priority.must, Status.met)]),
    ]);
    expect(totalScore(cat), closeTo(2 / 3, 1e-9));
  });

  group('evaluateGate', () {
    test('passes when everything is met and automated', () {
      expect(evaluateGate(fullyMet()).passed, isTrue);
    });

    test('fails on unmet must and names it', () {
      final r = evaluateGate(fullyMet(override: {'ASYNC-01': Status.notMet}));
      expect(r.passed, isFalse);
      expect(r.reasons.join('\n'), contains('ASYNC-01'));
    });

    test('fails on open P1 finding', () {
      final r = evaluateGate(fullyMet(findings: [f('F-001', Severity.p1)]));
      expect(r.passed, isFalse);
      expect(r.reasons.join('\n'), contains('F-001'));
    });

    test('closed P1 and open P2 do not block', () {
      final r = evaluateGate(fullyMet(findings: [
        f('F-001', Severity.p1, open: false),
        f('F-002', Severity.p2),
      ]));
      expect(r.passed, isTrue);
    });

    test('fails when COMPAT maturity 2 is below gate minimum 3', () {
      final r = evaluateGate(fullyMet(notAutomated: {'COMPAT-01'}));
      expect(r.passed, isFalse);
      expect(r.reasons.join('\n'), contains('COMPAT'));
    });

    test('ignores dimension with gateMinMaturity null', () {
      // MARKET has maturity 0 in fullyMet() but no gate minimum.
      expect(evaluateGate(fullyMet()).passed, isTrue);
    });

    test('pending criterion fails gate', () {
      final r = evaluateGate(fullyMet(override: {'API-03': null}));
      expect(r.passed, isFalse);
      expect(r.pending, ['API-03']);
    });
  });

  test('parseCatalog rejects unknown priority', () {
    expect(() => parseCatalog(_yamlWithPriority('X')), throwsFormatException);
  });

  test('parseCatalog reads statuses, ci flags and findings', () {
    final cat = parseCatalog(_yamlWithPriority('M'));
    final cr = cat.dimensions.single.criteria.single;
    expect(cr.priority, Priority.must);
    expect(cr.status, isNull);
    expect(cr.automatedInCi, isFalse);
    expect(cat.findings.single.severity, Severity.p1);
    expect(cat.findings.single.open, isTrue);
  });

  test('pending criterion fails gate with exit 2', () async {
    final dir = await Directory.systemTemp.createTemp('audit_score');
    final file = File('${dir.path}/criteria.yaml')
      ..writeAsStringSync(_yamlWithPriority('M'));
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/score.dart', file.path],
    );
    expect(result.exitCode, 2, reason: '${result.stdout}${result.stderr}');
    await dir.delete(recursive: true);
  });
}

String _yamlWithPriority(String p) => '''
meta:
  audited_commit: abc
dimensions:
  - id: ASYNC
    weight: 2
    gate_min_maturity: 3
    criteria:
      - id: ASYNC-01
        priority: $p
        status: null
        automated_in_ci: false
        evidence: null
        findings: []
findings:
  - id: F-001
    severity: P1
    criterion: ASYNC-01
    freeze_relevant: false
    status: open
''';
