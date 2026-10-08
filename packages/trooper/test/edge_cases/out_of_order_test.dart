import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: Out of Order and Rapid Requests', () {
    test('rapid consecutive searches forward and update stream to latest result',
        () async {
      final query = TrooperQuery<String, ({String text})>(
        namespace: 'search',
        fetch: (param) async {
          // If searching 'a', simulate slow response; if 'ab', simulate fast response
          if (param.text == 'a') {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return 'Result for a';
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return 'Result for ab';
          }
        },
        config: const TrooperConfig(
          conflictPolicy: QueryConflictPolicy.forward,
          deduplicate: false,
        ),
      );

      final states = <String>[];
      final sub = query.stream.dataStream.listen(states.add);

      // User types 'a' then quickly 'ab'
      final f1 = query.get((text: 'a'));
      final f2 = query.get((text: 'ab'));

      final r1 = await f1;
      final r2 = await f2;

      // Under forward policy, caller 1 gets forwarded to 'ab' and the stream reflects 'ab'
      expect(r1, 'Result for ab');
      expect(r2, 'Result for ab');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(query.currentData((text: 'ab')), 'Result for ab');

      await sub.cancel();
      query.dispose();
    });
  });
}
