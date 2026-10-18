import 'package:test/test.dart';
import 'package:trooper_audit_tool/lcov.dart';

void main() {
  test('summarizes DA and BRDA records, "-" counts as not taken', () {
    const lcov = 'SF:a.dart\nDA:1,1\nDA:2,0\nBRDA:1,0,0,1\nBRDA:1,0,1,0\n'
        'BRDA:1,0,2,-\nend_of_record\n';
    final s = summarizeLcov(lcov);
    expect([s.lineHit, s.lineFound, s.branchHit, s.branchFound], [1, 2, 1, 3]);
    expect(s.linePct, closeTo(50, 1e-9));
    expect(s.branchPct, closeTo(100 / 3, 1e-9));
  });

  test('branchPct is null without BRDA records', () {
    expect(summarizeLcov('SF:a.dart\nDA:1,1\nend_of_record\n').branchPct,
        isNull);
  });
}
