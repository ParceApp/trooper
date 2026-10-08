import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: Invalidation vs In-Flight Request Races', () {
    test('calling invalidate() during in-flight fetch cancels queue and prevents cache overwrite',
        () async {
      final completer = Completer<String>();
      final query = TrooperQuery<String, ()>(
        namespace: 'race_invalidation',
        fetch: (_) => completer.future,
        config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
      );

      final states = <StatefulData<String>>[];
      final sub = query.stream.listen(states.add);

      // Start in-flight query
      final future = query.get(const ());
      await Future<void>.delayed(Duration.zero);

      expect(query.current(const ()).isLoading, isTrue);

      // Invalidate while fetch is still in flight
      query.invalidate();
      expect(query.current(const ()), isA<DataInitial<String>>());

      // The in-flight caller future should be cancelled with TrooperCancelledException
      expect(future, throwsA(isA<TrooperCancelledException>()));

      // Now complete the delayed background task (simulate late network response)
      completer.complete('Late Network Data');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Invalidation must NOT be overwritten by the late network response
      expect(query.current(const ()), isA<DataInitial<String>>());
      expect(query.cache.get(const QueryKey('race_invalidation', ())), isNull);

      await sub.cancel();
      query.dispose();
    });

    test('calling invalidateKey() cancels in-flight operation for that key without affecting other keys',
        () async {
      final compA = Completer<String>();
      final compB = Completer<String>();

      final keyedQuery = KeyedTrooperQuery<String, String, ()>(
        namespace: 'keyed_race_invalidation',
        fetch: (key, _) => key == 'A' ? compA.future : compB.future,
        config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
      );

      final futureA = keyedQuery.getKey('A', const ());
      final futureB = keyedQuery.getKey('B', const ());
      await Future<void>.delayed(Duration.zero);

      expect(keyedQuery.currentKey('A').isLoading, isTrue);
      expect(keyedQuery.currentKey('B').isLoading, isTrue);

      // Invalidate key A only
      keyedQuery.invalidateKey('A');
      expect(keyedQuery.currentKey('A'), isA<DataInitial<String>>());
      expect(keyedQuery.currentKey('B').isLoading, isTrue);

      // Future A threw cancellation
      expect(futureA, throwsA(isA<TrooperCancelledException>()));

      // Key B completes normally
      compB.complete('Data B');
      final resultB = await futureB;
      expect(resultB, 'Data B');
      expect(keyedQuery.currentKeyData('B'), 'Data B');

      // Complete late network response for A
      compA.complete('Data A Late');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Key A remains DataInitial and uncached
      expect(keyedQuery.currentKey('A'), isA<DataInitial<String>>());
      final keyA = QueryKey.keyed('keyed_race_invalidation', key: 'A', parameter: const ());
      expect(keyedQuery.cache.get(keyA), isNull);

      keyedQuery.dispose();
    });
  });
}
