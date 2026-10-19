import 'dart:async';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/concurrency/request_sequencer.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_trooper.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/storage/cache_entry.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/storage_envelope.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// A query-based [KeyedTrooper] managing keyed collections of asynchronous resources.
///
/// Each unique key [K] maintains an independent [StatefulData] state, while sharing:
/// - Partitioned in-memory caching via [CacheStore].
/// - Request coalescing and concurrency control via [TrooperQueryQueue].
/// - Diagnostic telemetry via [TelemetryHub].
///
/// Use `operator []` or `.key(key)` to acquire a bound [Accessor] for a specific entity key.
///
/// ### Example:
/// ```dart
/// final lectureQuery = KeyedQueryTrooper<String, Lecture, ()>(
///   namespace: 'lecture',
///   fetch: (id, _) => fetchLecture(id),
/// );
///
/// // Access single lecture via subscript operator:
/// final lecture101 = lectureQuery['math-101'];
/// final data = await lecture101.get();
///
/// // Watch all lectures collectively:
/// lectureQuery.watchAll().listen((map) {
///   print('Loaded ${map.length} lectures');
/// });
/// ```
class KeyedQueryTrooper<K extends Object, T, P extends Parameter>
    extends KeyedTrooper<K, T, P> {
  /// Creates a [KeyedQueryTrooper] with a standard fetch function.
  factory KeyedQueryTrooper({
    required String namespace,
    required Future<T> Function(K key, P param) fetch,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) => KeyedQueryTrooper.cancellable(
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

  /// Creates a [KeyedQueryTrooper] with cooperative cancellation support via [TrooperCancelToken].
  KeyedQueryTrooper.cancellable({
    required super.namespace,
    required this.fetch,
    this.codec,
    super.config,
    super.sideEffects,
    super.cache,
    super.queryQueue,
    super.telemetry,
    super.stream,
  });

  /// The underlying fetch function executed to retrieve data for a key.
  final Future<T> Function(K key, P param, TrooperCancelToken token) fetch;

  /// Optional codec for L2 storage serialization.
  final TrooperCodec<T>? codec;

  final RequestSequencer _sequencer = RequestSequencer();

  /// Subscript operator to acquire a bound [Accessor] targeting [key].
  @override
  Accessor<T, P> operator [](K key) => _KeyedBoundAccessor<K, T, P>(this, key);

  /// Reads the value for [key], returning cached data if fresh or fetching from source.
  Future<T> getKey(K key, P parameter, {bool forceRefresh = false}) async {
    final paramChanged = isParamChanged(key, parameter);
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
        final storage = storageFor(qKey);
        final currentCodec = codec;
        if (storage != null && currentCodec != null) {
          try {
            final serialized = await storage.read(qKey.storageKey);
            if (serialized != null) {
              final envelope = StorageEnvelope.tryDecode(serialized);
              if (envelope == null) {
                storage.delete(qKey.storageKey).ignore();
              } else if (envelope.isExpired) {
                if (config.stalePolicy ==
                    StalePolicy.keepStaleWhileRevalidate) {
                  final restoredData = currentCodec.decode(envelope.payload);
                  final restoredEntry = CacheEntry<T>(
                    restoredData,
                    createdAt: envelope.createdAt,
                    expiresAt: envelope.expiresAt,
                    timeToLive: envelope.timeToLive,
                    source: DataSource.storage,
                  );
                  cache.putEntry(qKey, restoredEntry);

                  if (telemetry.hasListeners) {
                    telemetry.emit(
                      CacheHitEvent(
                        qKey,
                        isFresh: false,
                        metadata: restoredEntry.metadata,
                      ),
                    );
                    telemetry.emit(SWRTriggeredEvent(qKey));
                  }

                  stream.emitRefreshing(
                    key,
                    restoredData,
                    metadata: restoredEntry.metadata,
                  );

                  _executeFetch(
                    key: key,
                    param: parameter,
                    qKey: qKey,
                    forceNew: false,
                    staleData: restoredData,
                  ).ignore();

                  return restoredData;
                } else {
                  storage.delete(qKey.storageKey).ignore();
                }
              } else {
                final restoredData = currentCodec.decode(envelope.payload);
                final restoredEntry = CacheEntry<T>(
                  restoredData,
                  createdAt: envelope.createdAt,
                  expiresAt: envelope.expiresAt,
                  timeToLive: envelope.timeToLive,
                  source: DataSource.storage,
                );
                cache.putEntry(qKey, restoredEntry);

                if (telemetry.hasListeners) {
                  telemetry.emit(
                    CacheHitEvent(
                      qKey,
                      isFresh: true,
                      metadata: restoredEntry.metadata,
                    ),
                  );
                }

                stream.emitData(
                  key,
                  restoredData,
                  metadata: restoredEntry.metadata,
                );
                return restoredData;
              }
            }
          } catch (_) {
            storage.delete(qKey.storageKey).ignore();
          }
        }
      }
    }

    // 3. Fall through to network fetch
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

  /// Forces a fresh get of [key], bypassing cache freshness.
  Future<T> refreshKey(K key, P parameter) =>
      getKey(key, parameter, forceRefresh: true);

  /// Triggers a fetch of [key] in the background without awaiting the result.
  void triggerKey(K key, P parameter, {bool forceRefresh = false}) {
    getKey(key, parameter, forceRefresh: forceRefresh).ignore();
  }

  @override
  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((key) => getKey(key, parameter, forceRefresh: forceRefresh)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  Future<Map<K, T>> refreshKeys(Iterable<K> keys, P parameter) =>
      getAll(keys, parameter, forceRefresh: true);

  @override
  void triggerKeys(Iterable<K> keys, P parameter, {bool forceRefresh = false}) {
    for (final key in keys) {
      triggerKey(key, parameter, forceRefresh: forceRefresh);
    }
  }

  /// Reads multiple keys concurrently and returns a map of their states.
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
        ).then<void>((_) => null).catchError((_) => null),
      ),
    );

    return Map.unmodifiable({for (final key in keys) key: stream.stateOf(key)});
  }

  /// Watches state updates for a single [key].
  StatefulStream<T> watchKey(K key, {P? initialParameter, bool eager = false}) {
    if (eager && initialParameter != null) {
      final state = currentKey(key);
      if (state is DataInitial ||
          isParamChanged(key, initialParameter) ||
          (config.hasCache &&
              cache.isStale(buildQueryKey(key, initialParameter)))) {
        getKey(key, initialParameter).ignore();
      }
    }
    return stream.streamOf(key);
  }

  /// Manually sets data for [key] in cache and stream, returning the set [data].
  T setKey(K key, T data, P parameter) {
    final qKey = buildQueryKey(key, parameter);

    if (config.hasCache) {
      cache.put(
        qKey,
        data,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
    }

    final entry = config.hasCache ? cache.getEntry<T>(qKey) : null;
    stream.emitData(key, data, metadata: entry?.metadata);
    if (telemetry.hasListeners) {
      telemetry.emit(DataSetEvent(qKey, source: DataSource.local));
    }

    final storage = storageFor(qKey);
    final currentCodec = codec;
    if (storage != null && currentCodec != null) {
      try {
        final serialized = currentCodec.encode(data);
        final now = DateTime.now();
        final envelope = StorageEnvelope(
          payload: serialized,
          createdAt: now,
          expiresAt: config.hasCache ? now.add(config.timeToLive) : null,
          timeToLiveMillis: config.hasCache
              ? config.timeToLive.inMilliseconds
              : null,
        );
        storage.write(qKey.storageKey, envelope.encode()).catchError((
          Object error,
          StackTrace stacktrace,
        ) {
          telemetry.emit(
            PersistenceErrorEvent(
              qKey,
              error: error,
              duration: Duration.zero,
              stackTrace: stacktrace,
            ),
          );
        });
      } catch (error, stacktrace) {
        telemetry.emit(
          PersistenceErrorEvent(
            qKey,
            error: error,
            duration: Duration.zero,
            stackTrace: stacktrace,
          ),
        );
      }
    }

    runSideEffect(() => sideEffects?.onData?.call(key, data, parameter));
    return data;
  }

  /// Recovers all keys that are currently in an error state by triggering [refreshKey].
  @override
  FutureOr<void> recover() {
    for (final key in stream.activeKeys) {
      if (stream.stateOf(key).isError) {
        final param = lastParamOf(key);
        if (param != null) {
          refreshKey(key, param).ignore();
        }
      }
    }
  }

  /// Purges cache, cancels in-flight requests, and refreshes keys that have active listeners.
  @override
  FutureOr<void> didChangeDependencies() {
    final params = Map<K, P>.of(lastParams);
    invalidate();
    queryQueue.cancelNamespace(namespace);
    if (config.refreshAfterChangeDependencies) {
      for (final key in stream.activeKeys) {
        if (stream.hasKeyListeners(key)) {
          final param = params[key];
          if (param != null) {
            refreshKey(key, param).ignore();
          }
        }
      }
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
    runSideEffect(() => sideEffects?.onRequestStarted?.call(key, param));

    final sequence = _sequencer.begin(qKey);
    bool? isLatest;
    // Settles exactly once; false if a newer request was applied already.
    bool claim() => isLatest ??= _sequencer.settle(qKey, sequence);

    try {
      var result = await queryQueue.execute<T>(
        key: qKey,
        forceRefresh: forceNew,
        deduplicate: config.deduplicate,
        conflictPolicy: config.conflictPolicy,
        timeout: config.timeout,
        retryPolicy: config.retryPolicy,
        action: (token) => fetch(key, param, token),
      );
      stopwatch.stop();

      if (claim() && !isParamChanged(key, param)) {
        if (config.hasCache) {
          cache.put(
            qKey,
            result,
            timeToLive: config.timeToLive,
            source: DataSource.network,
          );
        }

        final entry = config.hasCache ? cache.getEntry<T>(qKey) : null;

        // Persist to L2 storage asynchronously if configured
        final storage = storageFor(qKey);
        final currentCodec = codec;
        if (storage != null && currentCodec != null) {
          try {
            final serialized = currentCodec.encode(result);
            final now = DateTime.now();
            final envelope = StorageEnvelope(
              payload: serialized,
              createdAt: now,
              expiresAt: config.hasCache ? now.add(config.timeToLive) : null,
              timeToLiveMillis: config.hasCache
                  ? config.timeToLive.inMilliseconds
                  : null,
            );
            storage.write(qKey.storageKey, envelope.encode()).catchError((
              Object error,
              StackTrace stacktrace,
            ) {
              telemetry.emit(
                PersistenceErrorEvent(
                  qKey,
                  error: error,
                  duration: stopwatch.elapsed,
                  stackTrace: stacktrace,
                ),
              );
            });
          } catch (error, stacktrace) {
            telemetry.emit(
              PersistenceErrorEvent(
                qKey,
                error: error,
                duration: stopwatch.elapsed,
                stackTrace: stacktrace,
              ),
            );
            // Non-critical persistence failure
          }
        }

        stream.emitData(key, result, metadata: entry?.metadata);
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

      runSideEffect(() => sideEffects?.onData?.call(key, result, param));

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

      runSideEffect(
        () => sideEffects?.onError?.call(key, error, stackTrace, param),
      );

      if (error is! TrooperCancelledException &&
          claim() &&
          !isParamChanged(key, param)) {
        stream.emitError(
          key,
          error,
          stackTrace: stackTrace,
          staleData: staleData,
        );
      }

      rethrow;
    } finally {
      claim();
    }
  }
}

class _KeyedBoundAccessor<K extends Object, T, P extends Parameter>
    implements Accessor<T, P> {
  const _KeyedBoundAccessor(this._parent, this._key);
  final KeyedQueryTrooper<K, T, P> _parent;
  final K _key;

  @override
  StatefulStream<T> get stream => _parent.stream.streamOf(_key);

  @override
  StatefulStream<T> watch({P? initialParameter, bool eager = false}) =>
      _parent.watchKey(_key, initialParameter: initialParameter, eager: eager);

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) =>
      _parent.getKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  Future<T> refresh(P parameter) => _parent.refreshKey(_key, parameter);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) =>
      _parent.triggerKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  StatefulData<T> current() => _parent.currentKey(_key);

  @override
  T? currentData() => _parent.currentKeyData(_key);

  @override
  void invalidate() => _parent.invalidateKey(_key);
}

/// Convenience extension for parameterless [KeyedQueryTrooper] instances where `P` is `()`.
extension ParameterlessKeyedQueryTrooper<K extends Object, T>
    on KeyedQueryTrooper<K, T, ()> {
  /// Reads the value for [key] without requiring an explicit `()` parameter.
  Future<T> getKey(K key, {bool forceRefresh = false}) =>
      this.getKey(key, const (), forceRefresh: forceRefresh);

  /// Forces a fresh get of [key] without requiring an explicit `()` parameter.
  Future<T> refreshKey(K key) => this.refreshKey(key, const ());

  /// Triggers a fetch of [key] in the background without requiring an explicit `()` parameter.
  void triggerKey(K key, {bool forceRefresh = false}) =>
      this.triggerKey(key, const (), forceRefresh: forceRefresh);

  /// Watches state updates for a single [key] without requiring an explicit `()` parameter.
  StatefulStream<T> watchKey(K key, {bool eager = false}) =>
      this.watchKey(key, initialParameter: const (), eager: eager);

  /// Reads multiple keys concurrently without requiring an explicit `()` parameter.
  Future<Map<K, StatefulData<T>>> getMany(
    List<K> keys, {
    bool forceRefresh = false,
  }) => this.getMany(keys, const (), forceRefresh: forceRefresh);

  /// Reads values for multiple [keys] concurrently without requiring an explicit `()` parameter.
  Future<Map<K, T>> getAll(Iterable<K> keys, {bool forceRefresh = false}) =>
      this.getAll(keys, const (), forceRefresh: forceRefresh);

  /// Refreshes values for multiple [keys] concurrently without requiring an explicit `()` parameter.
  Future<Map<K, T>> refreshKeys(Iterable<K> keys) =>
      this.refreshKeys(keys, const ());

  /// Triggers background fetches for multiple [keys] without requiring an explicit `()` parameter.
  void triggerKeys(Iterable<K> keys, {bool forceRefresh = false}) =>
      this.triggerKeys(keys, const (), forceRefresh: forceRefresh);

  /// Manually sets data for [key] in cache and stream without requiring an explicit `()` parameter.
  T setKey(K key, T data) => this.setKey(key, data, const ());
}
