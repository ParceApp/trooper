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
  });
}
