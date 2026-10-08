import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperMutation', () {
    test('FIFO queueing guarantees sequential execution under high concurrency',
        () async {
      final executionOrder = <int>[];
      final mutation = TrooperMutation<int, ({int id})>(
        namespace: 'order_processor',
        action: (param) async {
          // Add artificial delay inversely proportional to id
          await Future<void>.delayed(Duration(milliseconds: 20 - param.id * 2));
          executionOrder.add(param.id);
          return param.id;
        },
      );

      // Launch 5 mutations concurrently in order 1, 2, 3, 4, 5
      final futures = [
        mutation((id: 1)),
        mutation((id: 2)),
        mutation((id: 3)),
        mutation((id: 4)),
        mutation((id: 5)),
      ];

      final results = await Future.wait(futures);

      expect(results, [1, 2, 3, 4, 5]);
      // Must maintain strict FIFO execution despite delays
      expect(executionOrder, [1, 2, 3, 4, 5]);

      mutation.dispose();
    });

    test('invalidateOnSuccess invalidates specified invalidatables', () async {
      var queryFetches = 0;
      final query = TrooperQuery<String, ()>(
        namespace: 'user_bio',
        fetch: (_) async => 'Bio v${++queryFetches}',
        config: const TrooperConfig(timeToLive: Duration(hours: 1)),
      );

      await query.get(const ());
      expect(query.currentData(const ()), 'Bio v1');
      expect(queryFetches, 1);

      // Mutation linked to query
      final mutation = TrooperMutation<void, ({String newBio})>(
        namespace: 'update_bio',
        action: (_) async {},
        invalidateOnSuccess: [query],
      );

      await mutation((newBio: 'New Content'));

      // Query should now be invalidated
      expect(query.current(const ()), isA<DataInitial<String>>());

      // Subsequent query get will trigger a fresh fetch
      await query.get(const ());
      expect(query.currentData(const ()), 'Bio v2');
      expect(queryFetches, 2);

      query.dispose();
      mutation.dispose();
    });

    test('error isolation: failing mutation does not block subsequent mutations',
        () async {
      var counter = 0;
      final mutation = TrooperMutation<int, ({bool shouldFail})>(
        namespace: 'robust_mutation',
        action: (param) async {
          counter++;
          if (param.shouldFail) {
            throw StateError('Simulated mutation error');
          }
          return counter;
        },
      );

      final req1 = mutation((shouldFail: true));
      final req2 = mutation((shouldFail: false));

      expect(req1, throwsA(isA<StateError>()));
      expect(await req2, 2);

      mutation.dispose();
    });

    test('sideEffects, stream states and reset on TrooperMutation', () async {
      var started = false;
      var completed = false;
      var failed = false;

      final mutation = TrooperMutation<String, ({String name})>(
        namespace: 'profile_update',
        action: (p) async {
          if (p.name == 'invalid') throw ArgumentError('Bad name');
          return 'Saved: ${p.name}';
        },
        sideEffects: TrooperMutationSideEffects(
          onStarted: (_) => started = true,
          onSuccess: (_, _) => completed = true,
          onError: (_, _, _) => failed = true,
        ),
      );

      final stateHistory = <StatefulData<String>>[];
      final sub = mutation.stream.listen(stateHistory.add);

      final successResult = await mutation((name: 'Bob'));
      expect(successResult, 'Saved: Bob');
      expect(started, isTrue);
      expect(completed, isTrue);

      try {
        await mutation((name: 'invalid'));
      } catch (_) {}
      expect(failed, isTrue);
      expect(mutation.stream.isError, isTrue);

      mutation.reset();
      expect(mutation.stream.isInitial, isTrue);

      await sub.cancel();
      mutation.dispose();
    });

    test('parameterless mutation, isLoading, didChangeDependencies, and disposed error', () async {
      var executed = false;
      final paramless = TrooperMutation<String, ()>(
        namespace: 'paramless_mut',
        action: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          executed = true;
          return 'Done';
        },
      );

      final callFuture = ParameterlessTrooperMutation(paramless)();
      await Future<void>.delayed(Duration.zero);
      expect(paramless.isLoading, isTrue);

      final result = await callFuture;
      expect(result, 'Done');
      expect(executed, isTrue);
      expect(paramless.isLoading, isFalse);

      final execResult = await ParameterlessTrooperMutation(paramless).execute();
      expect(execResult, 'Done');

      paramless.didChangeDependencies();
      expect(paramless.currentState, isA<DataInitial<String>>());

      paramless.invalidate();
      expect(paramless.currentState, isA<DataInitial<String>>());

      await paramless.dispose();
      await paramless.dispose(); // Double dispose should be safe

      expect(
        () => paramless.execute(const ()),
        throwsA(isA<StateError>()),
      );
    });

    test('cancellable mutation respects TrooperCancelToken and emits DataError on cancel', () async {
      final token = TrooperCancelToken();
      final mutation = TrooperMutation<String, ({String data})>.cancellable(
        namespace: 'cancellable_mut',
        action: (p, cancelToken) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          cancelToken.throwIfCancelled();
          return 'Result: ${p.data}';
        },
      );

      final future = mutation.execute((data: 'Important'), cancelToken: token);
      // Cancel mid-execution
      token.cancel('User cancelled mutation');

      expect(future, throwsA(isA<TrooperCancelledException>()));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(mutation.stream.isError, isTrue);
      expect(mutation.currentState.errorOrNull, isA<TrooperCancelledException>());

      mutation.dispose();
    });
  });
}
