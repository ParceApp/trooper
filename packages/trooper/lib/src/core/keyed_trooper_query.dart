import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// A query-based Trooper managing keyed collections of resources.
///
/// Each unique key [K] maintains an independent [StatefulData] state, while sharing:
/// - Partitioned in-memory caching via [CacheStore].
/// - Request coalescing and concurrency control via [RequestOrchestrator].
/// - Diagnostic telemetry via [TelemetryHub].
///
/// Use `operator []` or `.key(key)` to acquire a bound [Accessor] for a specific entity key.
///
/// ### Example:
/// ```dart
/// final lectureQuery = KeyedTrooperQuery<String, Lecture, ()>(
///   name: 'lecture',
///   fetch: (id, _) => fetchLecture(id),
/// );
///
/// // Access single lecture via subscript operator:
/// final lecture101 = lectureQuery['math-101'];
/// final data = await lecture101.get(());
///
/// // Watch all lectures collectively:
/// lectureQuery.watchAll().listen((map) {
///   print('Loaded ${map.length} lectures');
/// });
/// ```
class KeyedTrooperQuery<K extends Object, T, P extends Parameter>
    with LifecycleAware
    implements Invalidatable, KeyedAccessor<K, T, P> {
  /// Creates a [KeyedTrooperQuery] with a standard fetch function.
  factory KeyedTrooperQuery({
    required String namespace,
    required Future<T> Function(K key, P param) fetch,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) => KeyedTrooperQuery.cancellable(
    namespace: namespace,
    fetch: (key, param, _) => fetch(key, param),
    codec: codec,
    config: config,
    sideEffects: sideEffects,
    cache: cache,
    queryQueue: queryQueue,
    telemetry: telemetry,
    stream: stream,
  );

  /// Creates a [KeyedTrooperQuery] with cooperative cancellation support via [TrooperCancelToken].
  KeyedTrooperQuery.cancellable({
    required this.namespace,
    required this.fetch,
    this.codec,
    TrooperConfig? config,
    this.sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) : config = config ?? TrooperConfig.defaultConfig,
       _ownsCache = cache == null,
       _ownsQueryQueue = queryQueue == null,
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       stream = stream ?? KeyedStatefulStream<K, T>();

  final bool _ownsCache;
  final bool _ownsQueryQueue;

  /// Logical family name for this collection of queries.
  final String namespace;

  /// The underlying fetch function executed to retrieve data for a key.
  final Future<T> Function(K key, P param, TrooperCancelToken token) fetch;

  /// Optional codec for L2 storage serialization.
  final TrooperCodec<T>? codec;

  /// Optional side-effect callbacks for lifecycle hooks.
  final KeyedTrooperSideEffects<K, T, P>? sideEffects;

  /// Configuration defining TTL, stale policy, and persistence.
  final TrooperConfig config;

  /// In-memory cache store.
  final CacheStore cache;

  /// Concurrency query queue.
  final TrooperQueryQueue queryQueue;

  /// Telemetry hub.
  final TelemetryHub telemetry;

  /// Replay-enabled keyed stream manager.
  final KeyedStatefulStream<K, T> stream;

  final Map<K, P> _lastParams = {};
  bool _isDisposed = false;

  /// Returns the set of currently active keys.
  @override
  Set<K> get activeKeys => stream.activeKeys;

  /// Returns the count of currently active keys.
  @override
  int get count => stream.count;

  /// Returns the most recent parameter used for [key], or `null` if none.
  P? lastParamOf(K key) => _lastParams[key];

  /// Builds the unique [QueryKey] for [key].
  @protected
  QueryKey buildQueryKey(K key, P parameter) {
    _lastParams[key] = parameter;
    return QueryKey.keyed(namespace, key: key, parameter: parameter);
  }

  /// Returns a read-only [KeyedAccessor] facade over this keyed query.
  late final KeyedAccessor<K, T, P> accessor = KeyedTrooperAccessor<K, T, P>(
    accessorFactory: (k) => this[k],
    stream: stream,
    onInvalidate: invalidate,
    onInvalidateKey: invalidateKey,
    onRefresh: () async {
      invalidate();
      return currentDataMap;
    },
  );

  /// Subscript operator to acquire a bound [Accessor] targeting [key].
  @override
  Accessor<T, P> operator [](K key) => _KeyedBoundAccessor<K, T, P>(this, key);

  /// Key-specific bound accessor alias.
  @override
  Accessor<T, P> key(K key) => this[key];

  /// Synchronously returns all current key states.
  @override
  Map<K, StatefulData<T>> get currentStates => stream.currentStates;

  @override
  StatefulStream<Map<K, T>> watch(() parameter, {bool eager = true}) =>
      accessor.watch(parameter, eager: eager);

  @override
  Future<Map<K, T>> get(() parameter, {bool forceRefresh = false}) =>
      accessor.get(parameter, forceRefresh: forceRefresh);

  @override
  Future<Map<K, T>> refresh(() parameter) => accessor.refresh(parameter);

  @override
  void trigger(() parameter, {bool forceRefresh = false}) =>
      accessor.trigger(parameter, forceRefresh: forceRefresh);

  @override
  StatefulData<Map<K, T>> current(() parameter) => accessor.current(parameter);

  @override
  Map<K, T>? currentData(() parameter) => accessor.currentData(parameter);

  bool _isParamChanged(K key, P parameter) {
    final last = _lastParams[key];
    if (last == null) return false;
    return parameter != last;
  }

  /// Reads the value for [key], returning cached data if fresh or fetching from source.
  Future<T> getKey(K key, P parameter, {bool forceRefresh = false}) async {
    final paramChanged = _isParamChanged(key, parameter);
    final qKey = buildQueryKey(key, parameter);

    // 1. Check L1 Cache
    if (!forceRefresh && !paramChanged && config.hasCache) {
      final entry = cache.getEntry<T>(qKey);
      if (entry != null) {
        if (entry.isFresh) {
          if (telemetry.hasListeners) {
            telemetry.emit(
              CacheHitEvent(qKey, isFresh: true, metadata: entry.metadata),
            );
          }
          stream.emitData(key, entry.data, metadata: entry.metadata);
          return entry.data;
        }

        // Stale entry found
        if (telemetry.hasListeners) {
          telemetry.emit(
            CacheHitEvent(qKey, isFresh: false, metadata: entry.metadata),
          );
        }

        if (config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
          if (telemetry.hasListeners) {
            telemetry.emit(SWRTriggeredEvent(qKey));
          }
          stream.emitRefreshing(key, entry.data, metadata: entry.metadata);

          // Background revalidation
          _executeFetch(
            key: key,
            param: parameter,
            qKey: qKey,
            forceNew: false,
            staleData: entry.data,
          ).ignore();

          return entry.data;
        }
      }

      // 2. Check L2 Storage only if L1 missed (entry == null)
      if (entry == null) {
        final storage = config.storage;
        final currentCodec = codec;
        if (storage != null && currentCodec != null) {
          final serialized = await storage.read(qKey.storageKey);
          if (serialized != null) {
            try {
              final restoredData = currentCodec.decode(serialized);
              cache.put(
                qKey,
                restoredData,
                timeToLive: config.timeToLive,
                source: DataSource.storage,
              );
              final restoredEntry = cache.getEntry<T>(qKey);
              if (telemetry.hasListeners) {
                telemetry.emit(
                  CacheHitEvent(
                    qKey,
                    isFresh: true,
                    metadata: restoredEntry?.metadata,
                  ),
                );
              }
              stream.emitData(
                key,
                restoredData,
                metadata: restoredEntry?.metadata,
              );
              return restoredData;
            } catch (_) {
              storage.delete(qKey.storageKey).ignore();
            }
          }
        }
      }
    }

    // 3. Network Fetch
    final staleData = cache.get<T>(qKey) ?? stream.dataOf(key);
    if (forceRefresh &&
        staleData != null &&
        config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
      stream.emitRefreshing(key, staleData);
    } else {
      stream.emitLoading(key);
    }

    return await _executeFetch(
      key: key,
      param: parameter,
      qKey: qKey,
      forceNew: forceRefresh,
      staleData: staleData,
    );
  }

  /// Triggers a fetch of [key] in the background without awaiting the result.
  void triggerKey(K key, P parameter, {bool forceRefresh = false}) {
    getKey(key, parameter, forceRefresh: forceRefresh).ignore();
  }

  /// Forces a fresh read of [key], bypassing cache freshness.
  Future<T> refreshKey(K key, P parameter) =>
      getKey(key, parameter, forceRefresh: true);

  /// Reads multiple keys concurrently, returning a map of all results.
  Future<Map<K, StatefulData<T>>> getMany(
    List<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) async {
    await Future.wait(
      keys.map(
        (key) => getKey(
          key,
          parameter,
          forceRefresh: forceRefresh,
        ).then<void>((_) {}).catchError((_) {}),
      ),
    );

    return Map.unmodifiable({for (final key in keys) key: stream.stateOf(key)});
  }

  /// Watches state updates for a single [key].
  StatefulStream<T> watchKey(K key, P parameter, {bool eager = true}) {
    if (eager) {
      final state = currentKey(key);
      if (state is DataInitial ||
          _isParamChanged(key, parameter) ||
          (config.hasCache && cache.isStale(buildQueryKey(key, parameter)))) {
        getKey(key, parameter).ignore();
      }
    }
    return stream.streamOf(key);
  }

  /// Returns the current state for [key] synchronously.
  StatefulData<T> currentKey(K key) => stream.stateOf(key);

  /// Returns the unwrapped data payload for [key] synchronously, or `null`.
  T? currentKeyData(K key) => stream.dataOf(key);

  /// Returns an immutable map of all keys with loaded data.
  @override
  Map<K, T> get currentDataMap => stream.currentDataMap;

  /// Returns a stream emitting the entire map of keys and their states whenever any changes.
  @override
  Stream<Map<K, StatefulData<T>>> watchAll() => stream.watchAll();

  /// Returns a stream emitting the active key set whenever keys are added or removed.
  @override
  Stream<Set<K>> watchKeys() => stream.watchKeys();

  /// Manually sets data for [key] in cache and stream, returning the set [data].
  T setKey(K key, T data, P parameter) {
    final qKey = buildQueryKey(key, parameter);

    cache.put(
      qKey,
      data,
      timeToLive: config.timeToLive,
      source: DataSource.local,
    );

    final entry = cache.getEntry<T>(qKey);
    stream.emitData(key, data, metadata: entry?.metadata);
    return data;
  }

  /// Invalidates the cache entry, clears persistent storage, and resets state to [DataInitial] for [key].
  @override
  void invalidateKey(K key) {
    final param =
        _lastParams.remove(key) ?? (const () is P ? const () as P : null);
    if (param != null) {
      final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
      cache.remove(qKey);
      final storage = config.storage;
      if (storage != null) {
        storage.delete(qKey.storageKey).ignore();
      }
      if (telemetry.hasListeners) {
        telemetry.emit(CacheInvalidatedEvent(qKey));
      }
    } else {
      cache.removeWhere(
        (qKey) => qKey.matchesNameAndKey(name: namespace, entityKey: key),
      );
    }
    stream.emitInitial(key);
  }

  /// Invalidates all entries belonging to this query family. Implements [Invalidatable].
  @override
  void invalidate() {
    final storage = config.storage;
    for (final key in stream.activeKeys) {
      final param = _lastParams[key] ?? (const () is P ? const () as P : null);
      if (param != null) {
        final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
        cache.remove(qKey);
        if (storage != null) {
          storage.delete(qKey.storageKey).ignore();
        }
      }
      stream.emitInitial(key);
    }
    _lastParams.clear();
    cache.removeName(namespace);
    if (telemetry.hasListeners) {
      telemetry.emit(CacheInvalidatedEvent(QueryKey(namespace, const ())));
    }
  }

  /// Removes [key] from cache and closes its stream.
  Future<void> removeKey(K key) async {
    _lastParams.remove(key);
    cache.removeWhere(
      (qKey) => qKey.matchesNameAndKey(name: namespace, entityKey: key),
    );
    await stream.removeKey(key);
  }

  /// Clears all keys from this query family.
  Future<void> clearAll() async {
    _lastParams.clear();
    cache.removeName(namespace);
    await stream.clearAll();
  }

  @override
  void pause() {
    cache.pause();
  }

  @override
  FutureOr<void> resume() {
    cache.resume();
  }

  /// Recovers all keys that are currently in an error state by triggering [refreshKey].
  @override
  FutureOr<void> recover() {
    for (final key in stream.activeKeys) {
      if (stream.stateOf(key).isError) {
        final param =
            _lastParams[key] ?? (const () is P ? const () as P : null);
        if (param != null) {
          refreshKey(key, param).ignore();
        }
      }
    }
  }

  /// Purges cache, cancels in-flight requests, and refreshes keys that have active listeners.
  @override
  FutureOr<void> didChangeDependencies() {
    final params = Map<K, P>.of(_lastParams);
    invalidate();
    queryQueue.cancelNamespace(namespace);
    if (config.refreshAfterChangeDependencies) {
      for (final key in stream.activeKeys) {
        if (stream.hasKeyListeners(key)) {
          final param = params[key] ?? (const () is P ? const () as P : null);
          if (param != null) {
            refreshKey(key, param).ignore();
          }
        }
      }
    }
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _lastParams.clear();
    await stream.dispose();
    if (_ownsQueryQueue) {
      await queryQueue.dispose();
    }
    if (_ownsCache) {
      await cache.dispose();
    }
  }

  void _runSideEffect(FutureOr<void> Function()? callback) {
    if (callback == null) return;
    try {
      final result = callback();
      if (result is Future) {
        result.ignore();
      }
    } catch (_) {
      // Non-critical side-effect failure
    }
  }

  Future<T> _executeFetch({
    required K key,
    required P param,
    required QueryKey qKey,
    required bool forceNew,
    T? staleData,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (telemetry.hasListeners) {
      telemetry.emit(RequestStartedEvent(qKey));
    }
    _runSideEffect(() => sideEffects?.onRequestStarted?.call(key, param));

    try {
      var result = await queryQueue.execute<T>(
        key: qKey,
        forceRefresh: forceNew,
        deduplicate: config.deduplicate,
        conflictPolicy: config.conflictPolicy,
        action: (token) => fetch(key, param, token),
      );
      stopwatch.stop();
      if (sideEffects != null && sideEffects?.transformRequestResult != null) {
        _runSideEffect(() async {
          T transformation = await sideEffects!.transformRequestResult!.call(
            key,
            result,
            param,
          );
          result = transformation;
        });
      }

      if (config.hasCache) {
        cache.put(
          qKey,
          result,
          timeToLive: config.timeToLive,
          source: DataSource.network,
        );
      }

      final entry = cache.getEntry<T>(qKey);
      stream.emitData(key, result, metadata: entry?.metadata);

      final storage = config.storage;
      final currentCodec = codec;
      if (storage != null && currentCodec != null) {
        try {
          final serialized = currentCodec.encode(result);
          storage.write(qKey.storageKey, serialized).ignore();
        } catch (_) {}
      }

      if (telemetry.hasListeners) {
        telemetry.emit(
          RequestCompletedEvent(
            qKey,
            duration: stopwatch.elapsed,
            source: DataSource.network,
          ),
        );
      }

      _runSideEffect(() => sideEffects?.onData?.call(key, result, param));

      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (telemetry.hasListeners) {
        telemetry.emit(
          RequestErrorEvent(
            qKey,
            error: error,
            duration: stopwatch.elapsed,
            stackTrace: stackTrace,
          ),
        );
      }

      stream.emitError(
        key,
        error,
        stackTrace: stackTrace,
        staleData: staleData,
      );

      _runSideEffect(
        () => sideEffects?.onError?.call(key, error, stackTrace, param),
      );

      rethrow;
    }
  }
}

class _KeyedBoundAccessor<K extends Object, T, P extends Parameter>
    implements Accessor<T, P> {
  const _KeyedBoundAccessor(this._parent, this._key);
  final KeyedTrooperQuery<K, T, P> _parent;
  final K _key;

  @override
  StatefulStream<T> watch(P parameter, {bool eager = true}) =>
      _parent.watchKey(_key, parameter, eager: eager);

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) =>
      _parent.getKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  Future<T> refresh(P parameter) => _parent.refreshKey(_key, parameter);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) =>
      _parent.triggerKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  StatefulData<T> current(P parameter) => _parent.currentKey(_key);

  @override
  T? currentData(P parameter) => _parent.currentKeyData(_key);

  @override
  void invalidate() => _parent.invalidateKey(_key);
}

/// Convenience extension for parameterless [KeyedTrooperQuery] instances where `P` is `()`.
extension ParameterlessKeyedTrooperQuery<K extends Object, T>
    on KeyedTrooperQuery<K, T, ()> {
  /// Reads the value for [key] without requiring an explicit `()` parameter.
  Future<T> getKey(K key, {bool forceRefresh = false}) =>
      this.getKey(key, const (), forceRefresh: forceRefresh);

  /// Forces a fresh get of [key] without requiring an explicit `()` parameter.
  Future<T> refreshKey(K key) => this.refreshKey(key, const ());

  /// Triggers a fetch of [key] in the background without requiring an explicit `()` parameter.
  void triggerKey(K key, {bool forceRefresh = false}) =>
      this.triggerKey(key, const (), forceRefresh: forceRefresh);

  /// Watches state updates for a single [key] without requiring an explicit `()` parameter.
  StatefulStream<T> watchKey(K key, {bool eager = true}) =>
      this.watchKey(key, const (), eager: eager);

  /// Reads multiple keys concurrently without requiring an explicit `()` parameter.
  Future<Map<K, StatefulData<T>>> getMany(
    List<K> keys, {
    bool forceRefresh = false,
  }) => this.getMany(keys, const (), forceRefresh: forceRefresh);

  /// Manually sets data for [key] in cache and stream without requiring an explicit `()` parameter.
  T setKey(K key, T data) => this.setKey(key, data, const ());
}
