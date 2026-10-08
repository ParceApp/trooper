import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: Cache Stampede', () {
    test('500 simultaneous requests on expired key result in exactly 1 network fetch',
        () async {
      var networkFetches = 0;
      final completer = Completer<String>();

      final query = TrooperQuery<String, ()>(
        namespace: 'popular_item',
        fetch: (_) async {
          networkFetches++;
          return completer.future;
        },
        config: const TrooperConfig(
          timeToLive: Duration(milliseconds: 10),
          deduplicate: true,
        ),
      );

      // Launch 500 concurrent callers at the exact same millisecond
      final futures = List.generate(500, (_) => query.get(const ()));

      expect(networkFetches, 1);

      completer.complete('Popular Data Payload');
      final results = await Future.wait(futures);

      expect(results.length, 500);
      for (final r in results) {
        expect(r, 'Popular Data Payload');
      }
      expect(networkFetches, 1);

      query.dispose();
    });
  });
}
