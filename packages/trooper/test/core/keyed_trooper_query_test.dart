import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';

void main() {
  group('KeyedTrooperQuery', () {
    late MockStorageBackend storage;

    setUp(() {
      storage = MockStorageBackend();
    });

    test('key isolation: actions on key A do not impact key B', () async {
      final counts = <String, int>{};
      final query = KeyedTrooperQuery<String, String, ()>(
        namespace: 'users',
        fetch: (key, _) async {
          counts[key] = (counts[key] ?? 0) + 1;
          return 'User $key';
        },
        config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
      );

      final userA = await query.getKey('A', const ());
      final userB = await query.getKey('B', const ());

      expect(userA, 'User A');
      expect(userB, 'User B');
      expect(counts['A'], 1);
      expect(counts['B'], 1);

      // Refreshing key A should only refetch key A
      await query.refreshKey('A', const ());
      expect(counts['A'], 2);
      expect(counts['B'], 1);

      // Cache for B remains fresh
      final cachedB = await query.getKey('B', const ());
      expect(cachedB, 'User B');
      expect(counts['B'], 1);
    });

    test('bound accessor operator [] behaves identically to an Accessor',
        () async {
      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'orders',
        fetch: (id, _) async => 'Order #$id',
        config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
      );

      final order101 = query[101];
      expect(order101, isA<Accessor<String, ()>>());

      final res = await order101.get(const ());
      expect(res, 'Order #101');
      expect(order101.currentData(const ()), 'Order #101');
      expect(order101.current(const ()), isA<DataLoaded<String>>());
    });

    test('getMany fetches multiple keys concurrently and aggregates states',
        () async {
      final query = KeyedTrooperQuery<String, int, ()>(
        namespace: 'scores',
        fetch: (player, _) async => player.length * 10,
      );

      final results = await query.getMany(['Tom', 'Alexander', 'Bob'], const ());

      expect(results.length, 3);
      expect(results['Tom']?.dataOrNull, 30);
      expect(results['Alexander']?.dataOrNull, 90);
      expect(results['Bob']?.dataOrNull, 30);
      for (final state in results.values) {
        expect(state, isA<DataLoaded<int>>());
      }
    });

    test('removeKey cleans up cache, storage, and stream state', () async {
      final query = KeyedTrooperQuery<String, String, ()>(
        namespace: 'products',
        fetch: (sku, _) async => 'Product $sku',
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      await query.getKey('P1', const ());
      expect(query.activeKeys.contains('P1'), isTrue);
      expect(storage.writeCount, 1);

      await query.removeKey('P1');

      expect(query.activeKeys.contains('P1'), isFalse);
      expect(query.currentKey('P1'), isA<DataInitial<String>>());
      expect(storage.deleteCount, greaterThanOrEqualTo(1));
    });

    test('persists keyed data with StorageEnvelope and restores on hydration',
        () async {
      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'cached_items',
        fetch: (id, _) async => 'Item #$id',
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      await query.getKey(42, const ());

      // Check stored envelope
      final storedRaw = await storage.read(
        QueryKey.keyed(query.namespace, key: 42, parameter: const ()).storageKey,
      );
      expect(storedRaw, isNotNull);
      final envelope = StorageEnvelope.tryDecode(storedRaw!);
      expect(envelope, isNotNull);
      expect(envelope!.payload, 'Item #42');

      // Hydrate via fresh instance
      final restoredQuery = KeyedTrooperQuery<int, String, ()>(
        namespace: 'cached_items',
        fetch: (_, _) async => throw StateError('Should hit L2 storage'),
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      final restored = await restoredQuery.getKey(42, const ());
      expect(restored, 'Item #42');
      expect(restoredQuery.currentKey(42), isA<DataLoaded<String>>());

      query.dispose();
      restoredQuery.dispose();
    });

    test('getMany reads multiple keys in parallel', () async {
      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'batch_items',
        fetch: (id, _) async => 'Batch $id',
      );

      final results = await query.getMany([10, 20, 30], const ());
      expect(results.length, 3);
      expect(results[10]?.dataOrNull, 'Batch 10');
      expect(results[20]?.dataOrNull, 'Batch 20');
      expect(results[30]?.dataOrNull, 'Batch 30');

      query.dispose();
    });

    test('refreshKey and triggerKey on KeyedTrooperQuery', () async {
      var fetchCount = 0;
      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'refresh_test',
        fetch: (id, _) async {
          fetchCount++;
          return 'Value $id ($fetchCount)';
        },
      );

      final first = await query.getKey(1, const ());
      expect(first, 'Value 1 (1)');

      // refreshKey forces fresh fetch
      final refreshed = await query.refreshKey(1, const ());
      expect(refreshed, 'Value 1 (2)');
      expect(fetchCount, 2);

      // triggerKey triggers background fetch
      query.triggerKey(1, const (), forceRefresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fetchCount, 3);

      query.dispose();
    });

    test('lifecycle hooks pause, resume, recover, and didChangeDependencies', () async {
      var shouldFail = true;
      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'lifecycle_keyed',
        fetch: (id, _) async {
          if (shouldFail) throw StateError('Fetch failed');
          return 'Recovered $id';
        },
      );

      try {
        await query.getKey(1, const ());
      } catch (_) {}

      expect(query.currentKey(1).isError, isTrue);

      // Now fix failure and call recover
      shouldFail = false;
      query.recover();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(query.currentKey(1).dataOrNull, 'Recovered 1');

      query.pause();
      query.resume();
      query.didChangeDependencies();

      query.dispose();
    });

    test('operator [] returns functional KeyedBoundAccessor', () async {
      var fetchCount = 0;
      final query = KeyedTrooperQuery<String, String, ()>(
        namespace: 'subscript_query',
        fetch: (key, _) async => 'Val-$key-${++fetchCount}',
      );

      final accessor = query['item-1'];
      expect(accessor.currentData(const ()), isNull);
      expect(accessor.current(const ()), isA<DataInitial<String>>());

      final data = await accessor.get(const ());
      expect(data, 'Val-item-1-1');
      expect(accessor.currentData(const ()), 'Val-item-1-1');

      final refreshed = await accessor.refresh(const ());
      expect(refreshed, 'Val-item-1-2');

      accessor.trigger(const (), forceRefresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(accessor.currentData(const ()), 'Val-item-1-3');

      final stream = accessor.watch(const (), false);
      expect(stream.currentData, 'Val-item-1-3');

      accessor.invalidate();
      expect(accessor.current(const ()), isA<DataInitial<String>>());

      query.dispose();
    });

    test('ParameterlessKeyedTrooperQuery extension methods', () async {
      var count = 0;
      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'paramless_kq',
        fetch: (id, _) async => 'Result $id (${++count})',
      );

      final val = await ParameterlessKeyedTrooperQuery(query).getKey(10);
      expect(val, 'Result 10 (1)');

      final refreshed = await ParameterlessKeyedTrooperQuery(query).refreshKey(10);
      expect(refreshed, 'Result 10 (2)');

      ParameterlessKeyedTrooperQuery(query).triggerKey(10, forceRefresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(query.currentKeyData(10), 'Result 10 (3)');

      ParameterlessKeyedTrooperQuery(query).setKey(10, 'Manual 10');
      expect(query.currentKeyData(10), 'Manual 10');

      final many = await ParameterlessKeyedTrooperQuery(query).getMany([10, 20]);
      expect(many[10]?.dataOrNull, 'Manual 10');
      expect(many[20]?.dataOrNull, 'Result 20 (4)');

      final watchStream = ParameterlessKeyedTrooperQuery(query).watchKey(10, eager: false);
      expect(watchStream.currentData, 'Manual 10');

      query.dispose();
    });

    test('L2 storage persistence, hydration, and expired envelope handling', () async {
      final storage = InMemoryStorageBackend();
      final codec = TrooperCodec.string;

      final query1 = KeyedTrooperQuery<String, String, ()>(
        namespace: 'persisted_kq',
        fetch: (id, _) async => 'FromNetwork-$id',
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      // Fetch from network and persist to storage
      final res1 = await query1.getKey('alpha', const ());
      expect(res1, 'FromNetwork-alpha');
      query1.dispose();

      // Query 2 without L1 cache should hydrate from L2 storage
      final query2 = KeyedTrooperQuery<String, String, ()>(
        namespace: 'persisted_kq',
        fetch: (id, _) async => 'NetworkReloaded-$id',
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      final hydrated = await query2.getKey('alpha', const ());
      expect(hydrated, 'FromNetwork-alpha');

      // Now test expired L2 with keepStaleWhileRevalidate
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final swrResult = await query2.getKey('alpha', const ());
      expect(swrResult, 'FromNetwork-alpha'); // Returns stale data immediately
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(query2.currentKeyData('alpha'), 'NetworkReloaded-alpha'); // Background revalidated

      query2.dispose();

      // Now test corrupted storage handling
      final corruptedKey = QueryKey.keyed('corrupted_kq', key: 'bad', parameter: (id: 'bad'));
      await storage.write(corruptedKey.storageKey, 'not-valid-json');

      final query3 = KeyedTrooperQuery<String, String, ({String id})>(
        namespace: 'corrupted_kq',
        fetch: (id, _) async => 'Fallback-$id',
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          stalePolicy: StalePolicy.discardStaleOnRefresh,
        ),
      );

      final fallback = await query3.getKey('bad', (id: 'bad'));
      expect(fallback, 'Fallback-bad');
      final newRaw = await storage.read(corruptedKey.storageKey);
      expect(newRaw, contains('Fallback-bad'));
      expect(newRaw, isNot('not-valid-json'));

      query3.dispose();
    });

    test('KeyedTrooperQuery sideEffects callbacks and error handling', () async {
      var started = false;
      var dataCallback = false;
      var errorCallback = false;

      final query = KeyedTrooperQuery<int, String, ()>(
        namespace: 'effects_kq',
        fetch: (id, _) async {
          if (id < 0) throw ArgumentError('Negative ID');
          return 'Valid $id';
        },
        sideEffects: KeyedTrooperSideEffects(
          onRequestStarted: (_, _) => started = true,
          onData: (_, _, _) => dataCallback = true,
          onError: (_, _, _, _) => errorCallback = true,
        ),
      );

      await query.getKey(1, const ());
      expect(started, isTrue);
      expect(dataCallback, isTrue);

      try {
        await query.getKey(-1, const ());
      } catch (_) {}
      expect(errorCallback, isTrue);

      query.dispose();
    });
  });
}
