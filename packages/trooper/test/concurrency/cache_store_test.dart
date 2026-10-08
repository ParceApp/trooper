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

      cache.put(key, 'Expired Data', timeToLive: const Duration(milliseconds: 10));
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
  });
}
