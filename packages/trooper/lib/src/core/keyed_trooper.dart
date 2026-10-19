import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/storage/storage_backend.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// Abstract base class for all keyed resource collections in Trooper.
///
/// Implements [KeyedAccessor] and [LifecycleAware], managing:
/// - Keyed reactive state broadcasting through [stream].
/// - In-memory L1 cache through [cache].
/// - Concurrency, deduplication, and cancellation through [queryQueue].
/// - Diagnostic telemetry through [telemetry].
/// - Configuration parameters through [config].
/// - Per-key parameter tracking through [_lastParams].
abstract class KeyedTrooper<K extends Object, T, P extends Parameter>
    with LifecycleAware
    implements Invalidatable {
  /// Creates a [KeyedTrooper] with the specified [namespace] and dependencies.
  KeyedTrooper({
    required this.namespace,
    this.sideEffects,
    TrooperConfig? config,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) : config = config ?? defaultConfig,
       _ownsCache = (cache == null),
       _ownsQueryQueue = (queryQueue == null),
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       stream = stream ?? KeyedStatefulStream<K, T>();

  /// Global default configuration used when no custom config is specified.
  static TrooperConfig get defaultConfig => TrooperConfig.defaultConfig;

  final bool _ownsCache;
  final bool _ownsQueryQueue;

  /// Logical name of this query or resource collection family.
  final String namespace;

  /// Configuration defining TTL, stale policy, and persistence.
  final TrooperConfig config;

  /// Optional side-effect callbacks for lifecycle hooks.
  final KeyedTrooperSideEffects<K, T, P>? sideEffects;

  /// In-memory L1 cache store.
  final CacheStore cache;

  /// Concurrency and request queue.
  final TrooperQueryQueue queryQueue;

  /// Telemetry hub for diagnostic events.
  final TelemetryHub telemetry;

  /// Keyed stateful stream emitting [StatefulData] transitions per key.
  final KeyedStatefulStream<K, T> stream;

  final Map<K, P> _lastParams = {};
  bool _isDisposed = false;

  /// Whether this keyed trooper collection has been disposed.
  bool get isDisposed => _isDisposed;

  /// Internal tracking map of the most recently used parameters for each key.
  @protected
  Map<K, P> get lastParams => _lastParams;

  /// The parameter used for the most recent operation on [key], or `null` if none has been recorded yet.
  P? lastParamOf(K key) => _lastParams[key];

  /// Records the last executed parameter for [key].
  @protected
  void recordParam(K key, P parameter) {
    _lastParams[key] = parameter;
  }

  /// Builds the unique [QueryKey] for [key] and [parameter] and records the parameter.
  @protected
  QueryKey buildQueryKey(K key, P parameter) {
    recordParam(key, parameter);
    return QueryKey.keyed(namespace, key: key, parameter: parameter);
  }

  bool _reportedUnstableStorageKey = false;

  /// The L2 backend to use for [key], or `null` if no storage is configured
  /// or [key] has no stable storage key (see [QueryKey.hasStableStorageKey]).
  ///
  /// Reports the first unstable key as a [PersistenceErrorEvent].
  @protected
  StorageBackend? storageFor(QueryKey key) {
    final storage = config.storage;
    if (storage == null || key.hasStableStorageKey) return storage;
    if (!_reportedUnstableStorageKey) {
      _reportedUnstableStorageKey = true;
      telemetry.emit(
        PersistenceErrorEvent(
          key,
          error: TrooperStorageException(
            'L2 storage skipped for ${key.describe()}: parameter or key has '
            'no stable toString(), so unequal values would share a storage key.',
          ),
          duration: Duration.zero,
        ),
      );
    }
    return null;
  }

  /// Checks whether [parameter] differs from the last parameter used for [key].
  @protected
  bool isParamChanged(K key, P parameter) {
    final last = _lastParams[key];
    if (last == null) return false;
    return parameter != last;
  }

  /// Safely executes an asynchronous side-effect callback without letting exceptions escape.
  @protected
  void runSideEffect(FutureOr<void> Function()? callback) {
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

  // --- KeyedAccessor Facade ---

  /// Read-only [KeyedAccessor] facade over this keyed trooper.
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

  Accessor<T, P> operator [](K key);

  Accessor<T, P> key(K key) => this[key];

  Map<K, StatefulData<T>> get currentStates => stream.currentStates;

  Map<K, T> get currentDataMap => stream.currentDataMap;

  Set<K> get activeKeys => stream.activeKeys;

  int get count => stream.count;

  Stream<Map<K, StatefulData<T>>> watchAll() => stream.watchAll();

  Stream<Set<K>> watchKeys() => stream.watchKeys();

  // --- Collection-level Accessor<Map<K, T>, ()> delegation ---

  StatefulStream<Map<K, T>> watch({()? initialParameter, bool eager = false}) =>
      accessor.watch(initialParameter: initialParameter, eager: eager);

  Future<Map<K, T>> get(() parameter, {bool forceRefresh = false}) =>
      accessor.get(parameter, forceRefresh: forceRefresh);

  Future<Map<K, T>> refresh(() parameter) => accessor.refresh(parameter);

  void trigger(() parameter, {bool forceRefresh = false}) =>
      accessor.trigger(parameter, forceRefresh: forceRefresh);

  StatefulData<Map<K, T>> current() => accessor.current();

  Map<K, T>? currentData() => accessor.currentData();

  // --- Single Key State Queries ---

  /// Returns the current state for [key] synchronously.
  StatefulData<T> currentKey(K key) => stream.stateOf(key);

  /// Returns the unwrapped data payload for [key] synchronously, or `null`.
  T? currentKeyData(K key) => stream.dataOf(key);

  // --- Invalidation & Cleanup ---

  /// Invalidates the cache entry, clears persistent storage, and resets state to [DataInitial] for [key].
  void invalidateKey(K key) {
    queryQueue.cancelWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    final param = _lastParams.remove(key);
    if (param != null) {
      final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
      final storage = storageFor(qKey);
      if (storage != null) {
        storage.delete(qKey.storageKey).ignore();
      }
      if (telemetry.hasListeners) {
        telemetry.emit(CacheInvalidatedEvent(qKey));
      }
    }
    cache.removeWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    stream.emitInitial(key);
  }

  /// Invalidates all keys belonging to this query family. Implements [Invalidatable].
  @override
  void invalidate() {
    queryQueue.cancelNamespace(namespace);
    final storage = config.storage;
    for (final key in stream.activeKeys) {
      final param = _lastParams[key];
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

  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) => accessor.getAll(keys, parameter, forceRefresh: forceRefresh);

  Future<Map<K, T>> refreshKeys(Iterable<K> keys, P parameter) =>
      accessor.refreshKeys(keys, parameter);

  void triggerKeys(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) => accessor.triggerKeys(keys, parameter, forceRefresh: forceRefresh);

  /// Invalidates the cache entry and resets state to [DataInitial] for multiple [keys].
  void invalidateKeys(Iterable<K> keys) {
    for (final key in keys) {
      invalidateKey(key);
    }
  }

  /// Removes multiple [keys] from the stream, cache, and optional persistent storage.
  Future<void> removeKeys(Iterable<K> keys) async {
    for (final key in keys) {
      await removeKey(key);
    }
  }

  /// Removes [key] from the stream, cache, and optional persistent storage.
  Future<void> removeKey(K key) async {
    queryQueue.cancelWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    final param = _lastParams.remove(key);
    cache.removeWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    if (param != null) {
      final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
      final storage = storageFor(qKey);
      if (storage != null) {
        storage.delete(qKey.storageKey).ignore();
      }
    }
    await stream.removeKey(key);
  }

  /// Pauses cache expiration timers while backgrounded.
  @override
  void pause() {
    cache.pause();
  }

  /// Resumes cache expiration timers upon foregrounding.
  @override
  FutureOr<void> resume() {
    cache.resume();
  }

  /// Clears all keys from this query family, purging cache and resetting the stream.
  Future<void> clearAll() async {
    _lastParams.clear();
    cache.removeName(namespace);
    await stream.clearAll();
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
}
