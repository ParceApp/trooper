import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: SWR Exact Transition Sequences & Error Retention', () {
    test('QueryTrooper stream emits deterministic sequence on fresh fetch, SWR refresh, and SWR error',
        () async {
      var fetchCount = 0;
      var shouldThrow = false;
      final query = QueryTrooper<String, ()>(
        namespace: 'swr_sequence',
        fetch: (_) async {
          fetchCount++;
          if (shouldThrow) {
            throw StateError('Background network failure $fetchCount');
          }
          return 'Value $fetchCount';
        },
        config: const TrooperConfig(
          timeToLive: Duration(milliseconds: 20),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      final states = <StatefulData<String>>[];
      final sub = query.stream.listen(states.add);

      // 1. Initial fetch
      final firstResult = await query.get(const ());
      expect(firstResult, 'Value 1');

      await Future<void>.delayed(Duration.zero);
      expect(states.length, 3);
      expect(states[0], isA<DataInitial<String>>());
      expect(states[1], isA<DataLoading<String>>());
      expect(states[2], isA<DataLoaded<String>>());
      expect((states[2] as DataLoaded<String>).data, 'Value 1');

      // 2. Wait for TTL to expire
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 3. Trigger SWR background revalidation
      final secondResult = await query.get(const ());
      // Caller gets stale value immediately
      expect(secondResult, 'Value 1');

      // Allow background fetch to complete
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Sequence should now have received DataRefreshing then DataLoaded
      expect(states.length, 5);
      expect(states[3], isA<DataRefreshing<String>>());
      expect((states[3] as DataRefreshing<String>).data, 'Value 1');
      expect(states[4], isA<DataLoaded<String>>());
      expect((states[4] as DataLoaded<String>).data, 'Value 2');

      // 4. Wait for TTL to expire again, then test background network error
      await Future<void>.delayed(const Duration(milliseconds: 30));
      shouldThrow = true;

      final thirdResult = await query.get(const ());
      // Caller still gets stale value immediately
      expect(thirdResult, 'Value 2');

      // Allow background fetch failure to propagate
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Stream must transition to DataRefreshing, then DataError with staleData preserved
      expect(states.length, 7);
      expect(states[5], isA<DataRefreshing<String>>());
      expect((states[5] as DataRefreshing<String>).data, 'Value 2');
      expect(states[6], isA<DataError<String>>());
      final errorState = states[6] as DataError<String>;
      expect(errorState.staleData, 'Value 2');

      await sub.cancel();
      query.dispose();
    });

    test('KeyedQueryTrooper stream emits deterministic sequence per key on SWR refresh and error',
        () async {
      var callCount = 0;
      var fail = false;

      final keyed = KeyedQueryTrooper<int, String, ()>(
        namespace: 'keyed_swr_seq',
        fetch: (id, _) async {
          callCount++;
          if (fail) throw StateError('Fetch failed');
          return 'Data-$id-V$callCount';
        },
        config: const TrooperConfig(
          timeToLive: Duration(milliseconds: 20),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      final keyStates = <StatefulData<String>>[];
      final sub = keyed.stream.streamOf(1).listen(keyStates.add);

      // Initial get
      final d1 = await keyed.getKey(1, const ());
      expect(d1, 'Data-1-V1');

      await Future<void>.delayed(Duration.zero);
      expect(keyStates.length, 3);
      expect(keyStates[0], isA<DataInitial<String>>());
      expect(keyStates[1], isA<DataLoading<String>>());
      expect(keyStates[2], isA<DataLoaded<String>>());

      // Expire TTL
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // SWR get: caller gets stale data
      final d2 = await keyed.getKey(1, const ());
      expect(d2, 'Data-1-V1');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Refresh emitted
      expect(keyStates.length, 5);
      expect(keyStates[3], isA<DataRefreshing<String>>());
      expect(keyStates[4], isA<DataLoaded<String>>());
      expect((keyStates[4] as DataLoaded<String>).data, 'Data-1-V2');

      // SWR error fallback
      await Future<void>.delayed(const Duration(milliseconds: 30));
      fail = true;

      final d3 = await keyed.getKey(1, const ());
      expect(d3, 'Data-1-V2');

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(keyStates.length, 7);
      expect(keyStates[5], isA<DataRefreshing<String>>());
      expect(keyStates[6], isA<DataError<String>>());
      expect((keyStates[6] as DataError<String>).staleData, 'Data-1-V2');

      await sub.cancel();
      keyed.dispose();
    });
  });
}
