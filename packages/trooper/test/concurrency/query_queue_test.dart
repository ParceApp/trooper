import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

    test(
      'cancelNamespace cancels all matching active in-flight operations',
      () async {
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

        final f1Expectation = expectLater(
          f1,
          throwsA(isA<TrooperCancelledException>()),
        );
        final f2Expectation = expectLater(
          f2,
          throwsA(isA<TrooperCancelledException>()),
        );

        queue.cancelNamespace('auth', reason: 'Auth expired');

        await Future.wait([f1Expectation, f2Expectation]);

        c3.complete('Feed Data');
        expect(await f3, 'Feed Data');

        expect(queue.activeCount, 0);
        queue.dispose();
      },
    );

    group('forward', () {
      const oldKey = QueryKey('filter', (f: 'active'));
      const newKey = QueryKey('filter', (f: 'archived'));

      test('superseded caller gets the new result even if the old action '
          'ignores its token and resolves first', () async {
        final queue = TrooperQueryQueue();
        final c0 = Completer<String>();
        final c1 = Completer<String>();
        final f0 = queue.execute(key: oldKey, action: (_) => c0.future);
        final f1 = queue.execute(key: newKey, action: (_) => c1.future);

        c0.complete('active');
        await pumpEventQueue();
        c1.complete('archived');

        expect(await f0, 'archived');
        expect(await f1, 'archived');
        await queue.dispose();
      });

      test('superseded caller gets the new result if the old action '
          'honors its token', () async {
        final queue = TrooperQueryQueue();
        final c1 = Completer<String>();
        final f0 = queue.execute<String>(
          key: oldKey,
          action: (token) async {
            await Future<void>.value();
            token.throwIfCancelled();
            return 'active';
          },
        );
        final f1 = queue.execute(key: newKey, action: (_) => c1.future);

        await pumpEventQueue();
        c1.complete('archived');

        expect(await f0, 'archived');
        expect(await f1, 'archived');
        await queue.dispose();
      });

      test('superseded caller gets the new result if superseded while '
          'waiting for a retry', () {
        fakeAsync((async) {
          final queue = TrooperQueryQueue();
          String? r0;
          final f0 = queue.execute<String>(
            key: oldKey,
            retryPolicy: const RetryPolicy.linear(delay: Duration(seconds: 1)),
            action: (_) async => throw StateError('down'),
          );
          f0.then((v) => r0 = v, onError: (Object e) => r0 = '$e');
          async.elapse(const Duration(milliseconds: 100));

          queue
              .execute(
                key: newKey,
                action: (_) => Future.delayed(
                  const Duration(seconds: 3),
                  () => 'archived',
                ),
              )
              .ignore();
          async.elapse(const Duration(seconds: 5));

          expect(r0, 'archived');
          queue.dispose();
          async.flushMicrotasks();
        });
      });

      test('superseded caller receives the error of the new request', () async {
        final queue = TrooperQueryQueue();
        final c0 = Completer<String>();
        final f0 = queue.execute(key: oldKey, action: (_) => c0.future);
        final f1 = queue.execute<String>(
          key: newKey,
          action: (_) async => throw StateError('new failed'),
        );
        c0.complete('active');

        await expectLater(f0, throwsA(isA<StateError>()));
        await expectLater(f1, throwsA(isA<StateError>()));
        await queue.dispose();
      });

      test('forwarding chains across several supersessions', () async {
        final queue = TrooperQueryQueue();
        final c0 = Completer<String>();
        final c1 = Completer<String>();
        final c2 = Completer<String>();
        final f0 = queue.execute(key: oldKey, action: (_) => c0.future);
        final f1 = queue.execute(key: newKey, action: (_) => c1.future);
        final f2 = queue.execute(
          key: const QueryKey('filter', (f: 'all')),
          action: (_) => c2.future,
        );
        c0.complete('active');
        c1.complete('archived');
        await pumpEventQueue();
        c2.complete('all');

        expect(await f0, 'all');
        expect(await f1, 'all');
        expect(await f2, 'all');
        await queue.dispose();
      });
    });
  });
}
