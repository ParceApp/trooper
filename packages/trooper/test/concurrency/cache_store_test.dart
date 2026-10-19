import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('CacheStore', () {
    test('put and get store and retrieve values with metadata', () {
      final cache = CacheStore();
      const key = QueryKey('users', (id: 1));

      cache.put(key, 'Alice', timeToLive: const Duration(minutes: 10));

      expect(cache.size, 1);
      expect(cache.containsKey(key), isTrue);
      expect(cache.isFresh(key), isTrue);
      expect(cache.isStale(key), isFalse);
      expect(cache.get<String>(key), 'Alice');

      cache.dispose();
    });

    test('stale entry detection and allowExpired eviction', () async {
      final cache = CacheStore();
      const key = QueryKey('temp', ());

      cache.put(
        key,
        'Expired Data',
        timeToLive: const Duration(milliseconds: 10),
      );
      expect(cache.isFresh(key), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(cache.isStale(key), isTrue);
      expect(cache.isFresh(key), isFalse);

      // get with allowExpired false should evict the entry
      expect(cache.get<String>(key, allowExpired: false), isNull);
      expect(cache.containsKey(key), isFalse);

      cache.dispose();
    });

    test('invalidation stream and namespace invalidation', () async {
      final cache = CacheStore();
      const k1 = QueryKey('auth', (type: 'token'));
      const k2 = QueryKey('auth', (type: 'refresh'));
      const k3 = QueryKey('profile', ());

      cache.put(k1, 'token_val');
      cache.put(k2, 'refresh_val');
      cache.put(k3, 'profile_val');

      final invalidated = <QueryKey>[];
      final sub = cache.invalidationStream.listen(invalidated.add);

      cache.invalidateNamespace('auth');
      await Future<void>.delayed(Duration.zero);

      expect(invalidated.length, 2);
      expect(invalidated.contains(k1), isTrue);
      expect(invalidated.contains(k2), isTrue);

      expect(cache.isStale(k1), isTrue);
      expect(cache.isStale(k2), isTrue);
      expect(cache.isFresh(k3), isTrue);

      await sub.cancel();
      cache.dispose();
    });

    test('putEntry and keys snapshot', () {
      final cache = CacheStore();
      const k1 = QueryKey('item', (id: 1));
      final entry = CacheEntry<String>('Value1', source: DataSource.network);

      cache.putEntry(k1, entry);
      expect(cache.keys, {k1});
      expect(cache.getEntry<String>(k1)?.source, DataSource.network);

      cache.dispose();
    });

    test('remove, removeWhere, removeName, clear', () {
      final cache = CacheStore();
      const k1 = QueryKey('user', (id: 1));
      const k2 = QueryKey('user', (id: 2));
      const k3 = QueryKey('order', (id: 99));

      cache.put(k1, 'u1');
      cache.put(k2, 'u2');
      cache.put(k3, 'o99');

      cache.remove(k1);
      expect(cache.containsKey(k1), isFalse);
      expect(cache.size, 2);

      cache.removeName('user');
      expect(cache.containsKey(k2), isFalse);
      expect(cache.size, 1);

      cache.removeWhere((k) => k.name == 'order');
      expect(cache.size, 0);

      cache.put(k1, 'u1');
      cache.clear();
      expect(cache.size, 0);

      cache.dispose();
    });

    test('invalidate and invalidateWhere', () {
      final cache = CacheStore();
      const k1 = QueryKey('feed', (page: 1));
      const k2 = QueryKey('feed', (page: 2));
      const k3 = QueryKey('settings', ());

      cache.put(k1, 'page1');
      cache.put(k2, 'page2');
      cache.put(k3, 'cfg');

      cache.invalidateWhere((k) => k.name == 'feed');
      expect(cache.isStale(k1), isTrue);
      expect(cache.isStale(k2), isTrue);
      expect(cache.isFresh(k3), isTrue);

      cache.invalidate();
      expect(cache.isStale(k3), isTrue);

      cache.dispose();
    });

    test('pause and resume lifecycle with periodic eviction', () async {
      final cache = CacheStore(
        evictionInterval: const Duration(milliseconds: 20),
      );
      const k1 = QueryKey('temp1', ());
      cache.put(k1, 'ephemeral', timeToLive: const Duration(milliseconds: 10));

      cache.pause();
      // pause immediately removes expired entries
      cache.resume();

      await Future<void>.delayed(const Duration(milliseconds: 35));
      // Periodic eviction should have cleared it
      expect(cache.containsKey(k1), isFalse);

      await cache.dispose();
      // Reads and writes after dispose throw; cleanup is a no-op.
      expect(() => cache.put(k1, 'data'), throwsStateError);
      expect(() => cache.get<String>(k1), throwsStateError);
      cache.clear();
    });

    group('maxEntries (LRU)', () {
      QueryKey k(int i) => QueryKey('lru', (id: i));

      test('evicts the least recently used entry beyond the limit', () {
        final cache = CacheStore(maxEntries: 2);
        cache.put(k(1), 'a');
        cache.put(k(2), 'b');
        cache.put(k(3), 'c');

        expect(cache.size, 2);
        expect(cache.containsKey(k(1)), isFalse);
        expect(cache.keys, {k(2), k(3)});
      });

      test('a read marks the entry as recently used', () {
        final cache = CacheStore(maxEntries: 2);
        cache.put(k(1), 'a');
        cache.put(k(2), 'b');
        expect(cache.get<String>(k(1)), 'a');
        cache.putEntry(k(3), CacheEntry<String>('c'));

        expect(cache.keys, {k(1), k(3)});
      });

      test('overwriting a key does not evict another entry', () {
        final cache = CacheStore(maxEntries: 2);
        cache.put(k(1), 'a');
        cache.put(k(2), 'b');
        cache.put(k(1), 'a2');

        expect(cache.keys, {k(1), k(2)});
        expect(cache.get<String>(k(1)), 'a2');
      });

      test('eviction does not notify invalidation listeners', () async {
        final cache = CacheStore(maxEntries: 1);
        final invalidated = <QueryKey>[];
        cache.invalidationStream.listen(invalidated.add);
        cache.put(k(1), 'a');
        cache.put(k(2), 'b');
        await pumpEventQueue();

        expect(invalidated, isEmpty);
        await cache.dispose();
      });

      test('is unbounded by default', () {
        final cache = CacheStore();
        for (var i = 0; i < 1000; i++) {
          cache.put(k(i), i);
        }
        expect(cache.maxEntries, isNull);
        expect(cache.size, 1000);
      });
    });
  });
}
