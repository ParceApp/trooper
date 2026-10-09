import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

void main() {
  group('MatchResult', () {
    test('handled property values', () {
      const result = MatchResult.handled;
      expect(result.isHandled, isTrue);
      expect(result.isUnhandled, isFalse);
    });

    test('unhandled property values', () {
      const result = MatchResult.unhandled;
      expect(result.isHandled, isFalse);
      expect(result.isUnhandled, isTrue);
    });

    test('fromBool factory matches expected values', () {
      expect(MatchResult.fromBool(true), equals(MatchResult.handled));
      expect(MatchResult.fromBool(false), equals(MatchResult.unhandled));
    });
  });
}
