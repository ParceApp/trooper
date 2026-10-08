import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('StatefulData State Model', () {
    test('DataInitial properties and equality', () {
      final initial = StatefulData<String>.initial();
      expect(initial.isInitial, isTrue);
      expect(initial.isLoading, isFalse);
      expect(initial.isLoaded, isFalse);
      expect(initial.isError, isFalse);
      expect(initial.isRefreshing, isFalse);
      expect(initial.dataOrNull, isNull);
      expect(initial.metadataOrNull, isNull);
      expect(initial.errorOrNull, isNull);

      const constInitial = DataInitial<String>();
      expect(initial, equals(constInitial));
      expect(initial.hashCode, constInitial.hashCode);
      expect(initial.toString(), 'DataInitial<String>()');
    });

    test('DataLoading properties, progress and equality', () {
      final loading = StatefulData<int>.loading(progress: 0.5);
      expect(loading.isInitial, isFalse);
      expect(loading.isLoading, isTrue);
      expect(loading.isLoaded, isFalse);
      expect(loading.isError, isFalse);
      expect(loading.isRefreshing, isFalse);
      expect(loading.dataOrNull, isNull);

      final otherLoading = DataLoading<int>(progress: 0.5);
      expect(loading, equals(otherLoading));
      expect(loading.hashCode, otherLoading.hashCode);
      expect(loading.toString(), 'DataLoading<int>(progress: 0.5)');

      final differentLoading = DataLoading<int>(progress: 0.9);
      expect(loading, isNot(equals(differentLoading)));
    });

    test('DataLoaded properties, metadata and equality', () {
      final meta = DataMetadata.now(
        source: DataSource.network,
        ttl: const Duration(minutes: 5),
      );
      final loaded = StatefulData<String>.loaded('hello', metadata: meta);

      expect(loaded.isInitial, isFalse);
      expect(loaded.isLoading, isFalse);
      expect(loaded.isLoaded, isTrue);
      expect(loaded.isError, isFalse);
      expect(loaded.isRefreshing, isFalse);
      expect(loaded.dataOrNull, 'hello');
      expect(loaded.metadataOrNull, meta);

      final otherLoaded = DataLoaded<String>('hello', metadata: meta);
      expect(loaded, equals(otherLoaded));
      expect(loaded.hashCode, otherLoaded.hashCode);
      expect(loaded.toString(), contains('DataLoaded<String>(data: hello'));
    });

    test('DataRefreshing extends DataLoaded and preserves data', () {
      final meta = DataMetadata.now(source: DataSource.cache);
      final refreshing = StatefulData<String>.refreshing(
        'stale_data',
        progress: 0.25,
        metadata: meta,
      );

      // SWR guarantee: it is loaded and has data!
      expect(refreshing.isLoaded, isTrue);
      expect(refreshing.isLoading, isTrue);
      expect(refreshing.isRefreshing, isTrue);
      expect(refreshing.dataOrNull, 'stale_data');
      expect(refreshing.metadataOrNull, meta);

      final sameRefreshing = DataRefreshing<String>(
        'stale_data',
        progress: 0.25,
        metadata: meta,
      );
      expect(refreshing, equals(sameRefreshing));
      expect(refreshing.hashCode, sameRefreshing.hashCode);
      expect(refreshing.toString(), contains('DataRefreshing<String>'));
    });

    test('DataError properties and stale data retention', () {
      final errorObj = StateError('network failed');
      final stack = StackTrace.current;
      final error = StatefulData<String>.error(
        errorObj,
        stackTrace: stack,
        staleData: 'retained_value',
      );

      expect(error.isError, isTrue);
      expect(error.isLoading, isFalse);
      expect(error.isLoaded, isFalse);
      expect(error.errorOrNull, errorObj);
      expect((error as DataError<String>).stackTrace, stack);
      expect(error.staleData, 'retained_value');

      final sameError = DataError<String>(
        errorObj,
        stackTrace: stack,
        staleData: 'retained_value',
      );
      expect(error, equals(sameError));
      expect(error.hashCode, sameError.hashCode);
      expect(error.toString(), contains('DataError<String>'));
    });

    test('when pattern matching executes correct callbacks', () {
      final initial = StatefulData<int>.initial();
      final loading = StatefulData<int>.loading(progress: 0.5);
      final loaded = StatefulData<int>.loaded(42);
      final refreshing = StatefulData<int>.refreshing(42, progress: 0.3);
      final error = StatefulData<int>.error('fail');

      expect(
        initial.when(
          initial: () => 'init',
          loading: (_) => 'load',
          loaded: (d, _) => 'data $d',
          error: (e, _, _) => 'err $e',
        ),
        'init',
      );

      expect(
        loading.when(
          initial: () => 'init',
          loading: (p) => 'load $p',
          loaded: (d, _) => 'data $d',
          error: (e, _, _) => 'err $e',
        ),
        'load 0.5',
      );

      expect(
        loaded.when(
          initial: () => 'init',
          loading: (_) => 'load',
          loaded: (d, _) => 'data $d',
          error: (e, _, _) => 'err $e',
        ),
        'data 42',
      );

      // When refreshing callback is provided
      expect(
        refreshing.when(
          initial: () => 'init',
          loading: (_) => 'load',
          loaded: (d, _) => 'data $d',
          refreshing: (d, p, _) => 'refresh $d $p',
          error: (e, _, _) => 'err $e',
        ),
        'refresh 42 0.3',
      );

      // When refreshing callback is omitted, falls back to loaded
      expect(
        refreshing.when(
          initial: () => 'init',
          loading: (_) => 'load',
          loaded: (d, _) => 'fallback loaded $d',
          error: (e, _, _) => 'err $e',
        ),
        'fallback loaded 42',
      );

      expect(
        error.when(
          initial: () => 'init',
          loading: (_) => 'load',
          loaded: (d, _) => 'data $d',
          error: (e, _, _) => 'err $e',
        ),
        'err fail',
      );
    });

    test('maybeWhen pattern matching executes or falls back to orElse', () {
      final loaded = StatefulData<String>.loaded('parce');

      expect(
        loaded.maybeWhen(
          loaded: (d, _) => 'matched $d',
          orElse: () => 'fallback',
        ),
        'matched parce',
      );

      expect(
        loaded.maybeWhen(
          initial: () => 'init',
          orElse: () => 'fallback',
        ),
        'fallback',
      );

      final refreshing = StatefulData<String>.refreshing('parce');
      expect(
        refreshing.maybeWhen(
          refreshing: (d, _, _) => 'refresh $d',
          orElse: () => 'fallback',
        ),
        'refresh parce',
      );

      expect(
        refreshing.maybeWhen(
          loaded: (d, _) => 'loaded $d',
          orElse: () => 'fallback',
        ),
        'loaded parce',
      );
    });

    test('map pattern matching transforms all concrete state instances', () {
      final states = <StatefulData<String>>[
        StatefulData.initial(),
        StatefulData.loading(),
        StatefulData.loaded('v'),
        StatefulData.refreshing('v'),
        StatefulData.error('err'),
      ];

      final labels = states.map((s) => s.map(
        initial: (_) => 'INITIAL',
        loading: (_) => 'LOADING',
        loaded: (_) => 'LOADED',
        refreshing: (_) => 'REFRESHING',
        error: (_) => 'ERROR',
      )).toList();

      expect(labels, ['INITIAL', 'LOADING', 'LOADED', 'REFRESHING', 'ERROR']);
    });
  });

  group('DataMetadata', () {
    test('properties, expiration calculation and age', () {
      final now = DateTime.now();
      final meta = DataMetadata(
        fetchedAt: now.subtract(const Duration(seconds: 10)),
        expiresAt: now.add(const Duration(minutes: 5)),
        source: DataSource.network,
      );

      expect(meta.isStale, isFalse);
      expect(meta.age.inSeconds, greaterThanOrEqualTo(10));
      expect(meta.timeToLive!.inSeconds, greaterThan(0));

      final expiredMeta = DataMetadata(
        fetchedAt: now.subtract(const Duration(minutes: 10)),
        expiresAt: now.subtract(const Duration(minutes: 1)),
        source: DataSource.cache,
      );
      expect(expiredMeta.isStale, isTrue);
      expect(expiredMeta.timeToLive, Duration.zero);

      final permanentMeta = DataMetadata(
        fetchedAt: now,
        expiresAt: null,
        source: DataSource.local,
      );
      expect(permanentMeta.isStale, isFalse);
      expect(permanentMeta.timeToLive, isNull);
    });

    test('copyWith and equality', () {
      final meta = DataMetadata.now(source: DataSource.storage);
      final updated = meta.copyWith(source: DataSource.network);

      expect(updated.source, DataSource.network);
      expect(updated.fetchedAt, meta.fetchedAt);
      expect(meta, isNot(equals(updated)));

      final identicalCopy = meta.copyWith();
      expect(identicalCopy, equals(meta));
      expect(identicalCopy.hashCode, meta.hashCode);
      expect(meta.toString(), contains('DataMetadata(source: DataSource.storage'));
    });
  });
}
