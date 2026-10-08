import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperConfig', () {
    test('default configuration values and aliases', () {
      const config = TrooperConfig();

      expect(config.timeToLive, const Duration(minutes: 1));
      expect(config.stalePolicy, StalePolicy.keepStaleWhileRevalidate);
      expect(config.conflictPolicy, QueryConflictPolicy.forward);
      expect(config.queryConflictPolicy, QueryConflictPolicy.forward);
      expect(config.deduplicate, isTrue);
      expect(config.hasCache, isTrue);
      expect(config.storage, isNull);
      expect(config.refreshAfterChangeDependencies, isTrue);
      expect(config.timeout, isNull);
      expect(config.retryPolicy, isNull);
    });

    test('TrooperConfig.noCache disables caching and sets discard policy', () {
      const noCache = TrooperConfig.noCache();

      expect(noCache.timeToLive, Duration.zero);
      expect(noCache.hasCache, isFalse);
      expect(noCache.stalePolicy, StalePolicy.discardStaleOnRefresh);
      expect(noCache.storage, isNull);
      expect(noCache.timeout, isNull);
      expect(noCache.retryPolicy, isNull);
    });

    test('copyWith updates individual fields', () {
      const initial = TrooperConfig();
      final storage = InMemoryStorageBackend();
      final retry = RetryPolicy.immediate(maxRetries: 3);
      final updated = initial.copyWith(
        timeToLive: const Duration(hours: 2),
        conflictPolicy: QueryConflictPolicy.cancel,
        deduplicate: false,
        refreshAfterChangeDependencies: false,
        stalePolicy: StalePolicy.discardStaleOnRefresh,
        storage: storage,
        timeout: const Duration(seconds: 10),
        retryPolicy: retry,
      );

      expect(updated.timeToLive, const Duration(hours: 2));
      expect(updated.conflictPolicy, QueryConflictPolicy.cancel);
      expect(updated.deduplicate, isFalse);
      expect(updated.refreshAfterChangeDependencies, isFalse);
      expect(updated.stalePolicy, StalePolicy.discardStaleOnRefresh);
      expect(updated.storage, storage);
      expect(updated.timeout, const Duration(seconds: 10));
      expect(updated.retryPolicy, retry);
    });

    test('static defaultConfig and setDefaultConfig', () {
      final original = TrooperConfig.defaultConfig;
      const custom = TrooperConfig(timeToLive: Duration(seconds: 45));

      TrooperConfig.setDefaultConfig(custom);
      expect(TrooperConfig.defaultConfig.timeToLive, const Duration(seconds: 45));

      // Restore
      TrooperConfig.setDefaultConfig(original);
      expect(TrooperConfig.defaultConfig.timeToLive, original.timeToLive);
    });
  });
}
