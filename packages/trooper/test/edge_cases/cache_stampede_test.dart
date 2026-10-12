import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: Cache Stampede & Request Coalescing', () {
    test('cold stampede: 500 simultaneous requests on empty cache execute exactly 1 fetch',
        () async {
      var networkFetches = 0;
      final completer = Completer<String>();

      final query = QueryTrooper<String, ()>(
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

    test('SWR stampede: 200 simultaneous requests on expired key receive stale data immediately with 1 background fetch',
        () async {
      var networkFetches = 0;
      final revalidationCompleter = Completer<String>();

      final query = QueryTrooper<String, ()>(
        namespace: 'swr_stampede',
        fetch: (_) async {
          networkFetches++;
          if (networkFetches == 1) {
            return 'Initial Value';
          }
          return revalidationCompleter.future;
        },
        config: const TrooperConfig(
          timeToLive: Duration(milliseconds: 20),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
          deduplicate: true,
        ),
      );

      // Populate initial cache
      final initial = await query.get(const ());
      expect(initial, 'Initial Value');
      expect(networkFetches, 1);

      // Wait for TTL to expire
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 200 simultaneous callers hit expired key
      final futures = List.generate(200, (_) => query.get(const ()));

      // In SWR mode, all 200 callers should complete immediately with stale data
      final results = await Future.wait(futures);
      expect(results.length, 200);
      for (final r in results) {
        expect(r, 'Initial Value');
      }

      // Exactly 1 background revalidation fetch should have been spawned
      expect(networkFetches, 2);

      // Complete the background revalidation
      revalidationCompleter.complete('Revalidated Fresh Value');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Subsequent get returns the fresh revalidated value
      final fresh = await query.get(const ());
      expect(fresh, 'Revalidated Fresh Value');

      query.dispose();
    });

    test('Keyed SWR stampede: 100 simultaneous requests on expired key in KeyedQueryTrooper coalesce into 1 fetch',
        () async {
      var fetches = 0;
      final revalCompleter = Completer<String>();

      final keyedQuery = KeyedQueryTrooper<int, String, ()>(
        namespace: 'keyed_swr_stampede',
        fetch: (key, _) async {
          fetches++;
          if (fetches == 1) return 'Key-$key-V1';
          return revalCompleter.future;
        },
        config: const TrooperConfig(
          timeToLive: Duration(milliseconds: 20),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
          deduplicate: true,
        ),
      );

      // Prime cache for key 42
      await keyedQuery.getKey(42, const ());
      expect(fetches, 1);

      // Wait for expiration
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 100 simultaneous callers for key 42
      final futures = List.generate(100, (_) => keyedQuery.getKey(42, const ()));
      final results = await Future.wait(futures);

      expect(results.length, 100);
      for (final r in results) {
        expect(r, 'Key-42-V1');
      }
      expect(fetches, 2);

      revalCompleter.complete('Key-42-V2');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(keyedQuery.currentKeyData(42), 'Key-42-V2');

      keyedQuery.dispose();
    });
  });
}
