import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperMutationQueue', () {
    test(
      'enforces strict FIFO order regardless of individual task duration',
      () async {
        final queue = TrooperMutationQueue();
        final executed = <String>[];

        final f1 = queue.add(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          executed.add('first');
          return 'r1';
        });

        final f2 = queue.add(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          executed.add('second');
          return 'r2';
        });

        final f3 = queue.add(() async {
          executed.add('third');
          return 'r3';
        });

        final results = await Future.wait([f1, f2, f3]);

        expect(results, ['r1', 'r2', 'r3']);
        expect(executed, ['first', 'second', 'third']);
        expect(queue.pendingCount, 0);

        queue.dispose();
      },
    );

    test('recovers and proceeds with next task if a task throws', () async {
      final queue = TrooperMutationQueue();

      final f1 = queue.add<int>(() async => throw StateError('Boom'));
      final f2 = queue.add<int>(() async => 42);

      expect(f1, throwsA(isA<StateError>()));
      expect(await f2, 42);

      queue.dispose();
    });

    test(
      'disposal cancels all pending queued tasks with TrooperCancelledException',
      () async {
        final queue = TrooperMutationQueue();
        final slow = Completer<void>();

        final errs = <Object>[];
        final f1 = queue.add<void>(() => slow.future)
          ..catchError((Object e) => errs.add(e));
        final f2 = queue.add<String>(() async => 'never 2')
          ..catchError((Object e) {
            errs.add(e);
            return '';
          });

        expect(queue.pendingCount, 2);

        await queue.dispose();

        slow.complete();
        await Future<void>.delayed(Duration.zero);

        expect(errs.length, 2);
        expect(errs[0], isA<TrooperCancelledException>());
        expect(errs[1], isA<TrooperCancelledException>());

        expect(f1, isNotNull);
        expect(f2, isNotNull);
      },
    );
  });
}
