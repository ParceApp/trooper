import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: Out of Order and Rapid Requests', () {
    test(
      'QueryConflictPolicy.forward: rapid consecutive searches forward and prevent cache pollution',
      () async {
        final query = QueryTrooper<String, ({String text})>(
          namespace: 'search_forward',
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

        final streamStates = <String>[];
        final sub = query.stream.dataStream.listen(streamStates.add);

        // User types 'a' then quickly 'ab'
        final f1 = query.get((text: 'a'));
        final f2 = query.get((text: 'ab'));

        final r1 = await f1;
        final r2 = await f2;

        // Under forward policy, caller 1 gets forwarded to 'ab' and the stream reflects 'ab'
        expect(r1, 'Result for ab');
        expect(r2, 'Result for ab');

        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Cache for 'ab' contains 'Result for ab'
        const keyAb = QueryKey('search_forward', (text: 'ab'));
        expect(query.cache.get<String>(keyAb), 'Result for ab');

        // Crucial: Cache for 'a' must NOT be polluted with 'Result for ab'
        const keyA = QueryKey('search_forward', (text: 'a'));
        expect(query.cache.get<String>(keyA), isNull);

        // Stream should only have received 'Result for ab', never an out-of-order 'Result for a'
        expect(streamStates, ['Result for ab']);

        await sub.cancel();
        query.dispose();
      },
    );

    test(
      'QueryConflictPolicy.cancel: previous in-flight request is aborted with TrooperCancelledException',
      () async {
        final query = QueryTrooper<String, ({String text})>(
          namespace: 'search_cancel',
          fetch: (param) async {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return 'Result for ${param.text}';
          },
          config: const TrooperConfig(
            conflictPolicy: QueryConflictPolicy.cancel,
            deduplicate: false,
          ),
        );

        // Call 1
        final f1 = query.get((text: 'first'));
        // Call 2 immediately supersedes Call 1
        final f2 = query.get((text: 'second'));

        // Call 1 throws TrooperCancelledException
        expect(f1, throwsA(isA<TrooperCancelledException>()));

        final r2 = await f2;
        expect(r2, 'Result for second');
        expect(query.currentData(), 'Result for second');

        query.dispose();
      },
    );

    test(
      'KeyedQueryTrooper forward policy prevents cache pollution across parameters for same entity key',
      () async {
        final keyedQuery = KeyedQueryTrooper<int, String, ({String filter})>(
          namespace: 'keyed_forward',
          fetch: (id, param) async {
            if (param.filter == 'all') {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return 'User-$id-All';
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return 'User-$id-Active';
            }
          },
          config: const TrooperConfig(
            conflictPolicy: QueryConflictPolicy.forward,
            deduplicate: false,
          ),
        );

        final f1 = keyedQuery.getKey(1, (filter: 'all'));
        final f2 = keyedQuery.getKey(1, (filter: 'active'));

        final r1 = await f1;
        final r2 = await f2;

        expect(r1, 'User-1-Active');
        expect(r2, 'User-1-Active');

        await Future<void>.delayed(const Duration(milliseconds: 60));

        // Key for (1, active) is cached
        final activeQKey = QueryKey.keyed(
          'keyed_forward',
          key: 1,
          parameter: (filter: 'active'),
        );
        expect(keyedQuery.cache.get<String>(activeQKey), 'User-1-Active');

        // Obsolete key for (1, all) is NOT polluted
        final allQKey = QueryKey.keyed(
          'keyed_forward',
          key: 1,
          parameter: (filter: 'all'),
        );
        expect(keyedQuery.cache.get<String>(allQKey), isNull);

        keyedQuery.dispose();
      },
    );
  });
}
