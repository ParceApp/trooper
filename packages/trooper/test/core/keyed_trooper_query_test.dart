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
    });
  });
}
