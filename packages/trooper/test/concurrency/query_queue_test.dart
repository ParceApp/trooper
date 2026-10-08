import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperQueryQueue', () {
    test('coalesces identical requests when deduplicate is true', () async {
      final queue = TrooperQueryQueue();
      const key = QueryKey('test', ());

      final completer = Completer<String>();
      var executions = 0;

      final f1 = queue.execute<String>(
        key: key,
        action: (_) {
          executions++;
          return completer.future;
        },
      );

      final f2 = queue.execute<String>(
        key: key,
        action: (_) {
          executions++;
          return completer.future;
        },
      );

      expect(queue.activeCount, 1);
      expect(executions, 1);

      completer.complete('Done');
      final r1 = await f1;
      final r2 = await f2;

      expect(r1, 'Done');
      expect(r2, 'Done');
      expect(queue.activeCount, 0);

      queue.dispose();
    });

    test('cancelNamespace cancels all matching active in-flight operations', () async {
      final queue = TrooperQueryQueue();
      const key1 = QueryKey.keyed('auth', key: 1, parameter: ());
      const key2 = QueryKey.keyed('auth', key: 2, parameter: ());
      const key3 = QueryKey('feed', ());

      final c1 = Completer<String>();
      final c2 = Completer<String>();
      final c3 = Completer<String>();

      final f1 = queue.execute(key: key1, action: (_) => c1.future);
      final f2 = queue.execute(key: key2, action: (_) => c2.future);
      final f3 = queue.execute(key: key3, action: (_) => c3.future);

      expect(queue.activeCount, 3);

      final f1Expectation = expectLater(f1, throwsA(isA<TrooperCancelledException>()));
      final f2Expectation = expectLater(f2, throwsA(isA<TrooperCancelledException>()));

      queue.cancelNamespace('auth', 'Auth expired');

      await Future.wait([f1Expectation, f2Expectation]);

      c3.complete('Feed Data');
      expect(await f3, 'Feed Data');

      expect(queue.activeCount, 0);
      queue.dispose();
    });
  });
}
