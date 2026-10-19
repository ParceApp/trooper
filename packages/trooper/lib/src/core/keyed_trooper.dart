import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/core/keyed_trooper_accessor.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/storage/storage_access.dart';
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
abstract base class KeyedTrooper<K extends Object, T, P extends Parameter>
    with LifecycleAware, StorageAccess
    implements Invalidatable {
  /// Creates a [KeyedTrooper] with the specified [namespace] and dependencies.
  @internal
  KeyedTrooper({
    required this.namespace,
    this.sideEffects,
    TrooperConfig? config,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    this.releaseUnwatchedKeys = false,
  }) : config = config ?? const TrooperConfig(),
       _ownsCache = (cache == null),
       _ownsQueryQueue = (queryQueue == null),
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       stream = KeyedStatefulStream<K, T>() {
    if (releaseUnwatchedKeys) stream.onKeyUnwatched = _scheduleRelease;
  }

  final bool _ownsCache;
  final bool _ownsQueryQueue;

  /// Logical name of this query or resource collection family.
  @override
  final String namespace;

  /// Configuration defining TTL, stale policy, and persistence.
  @override
  final TrooperConfig config;

  /// Optional side-effect callbacks for lifecycle hooks.
  final KeyedTrooperSideEffects<K, T, P>? sideEffects;

  /// In-memory L1 cache store.
  final CacheStore cache;

  /// Concurrency and request queue.
  final TrooperQueryQueue queryQueue;

  /// Telemetry hub for diagnostic events.
  @override
  final TelemetryHub telemetry;

  /// Keyed stateful stream emitting [StatefulData] transitions per key.
  @internal
  final KeyedStatefulStream<K, T> stream;

  /// Whether the in-memory state of a key is dropped once nobody watches it.
  ///
  /// By default (`false`) a keyed trooper keeps the latest state, the last
  /// parameter and similar per-key data of every key it has seen until
  /// [removeKey], [clearAll] or [dispose], so memory grows with the key space.
  ///
  /// With `true`, a key is released when it has no listener on its stream (and
  /// nobody listens to `stream.watchAll()` or `stream.watchKeys()`), no request
  /// for it is in flight and, for stream troopers, no upstream connection is
  /// open. Releasing keeps the L1 cache and L2 storage, so the next `getKey` or
  /// eager `watchKey` serves cached data instantly; bound the cache with
  /// `CacheStore(maxEntries: …)`. After release, [currentKeyData] returns
  /// `null`, and a per-key stream object obtained earlier is closed: call
  /// `watchKey` again instead of re-listening to an old stream.
  final bool releaseUnwatchedKeys;

  final Map<K, P> _lastParams = {};
  bool _isDisposed = false;

  /// Whether this keyed trooper collection has been disposed.
  bool get isDisposed => _isDisposed;

  /// Throws a [StateError] naming [operation] if this trooper has been
  /// disposed (see [LifecycleAware.dispose]).
  @internal
  void ensureNotDisposed(String operation) {
    if (_isDisposed) {
      throw StateError(
        'Cannot call $operation() on disposed $runtimeType "$namespace".',
      );
    }
  }

  /// Internal tracking map of the most recently used parameters for each key.
  @internal
  Map<K, P> get lastParams => _lastParams;

  /// The parameter used for the most recent operation on [key], or `null` if none has been recorded yet.
  P? lastParamOf(K key) => _lastParams[key];

  /// Records the last executed parameter for [key].
  @internal
  void recordParam(K key, P parameter) {
    _lastParams[key] = parameter;
  }

  /// Builds the unique [QueryKey] for [key] and [parameter] and records the parameter.
  @internal
  QueryKey buildQueryKey(K key, P parameter) {
    recordParam(key, parameter);
    return QueryKey.keyed(namespace, key: key, parameter: parameter);
  }

  /// Checks whether [parameter] differs from the last parameter used for [key].
  @internal
  bool isParamChanged(K key, P parameter) {
    final last = _lastParams[key];
    if (last == null) return false;
    return parameter != last;
  }

  /// Executes a side-effect callback without letting its failure break the
  /// request.
  ///
  /// A synchronous or asynchronous failure is reported to the current [Zone]
  /// as an uncaught error (like a failing stream listener), so it reaches
  /// `runZonedGuarded`, `PlatformDispatcher.onError` or a crash reporter.
  @internal
  void runSideEffect(FutureOr<void> Function()? callback) {
    if (callback == null) return;
    try {
      final result = callback();
      if (result is Future) {
        unawaited(result);
      }
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
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

  Map<K, StatefulData<T>> get currentStates => stream.currentStates;

  Map<K, T> get currentDataMap => stream.currentDataMap;

  Set<K> get activeKeys => stream.activeKeys;

  int get count => stream.count;

  Stream<Map<K, StatefulData<T>>> watchAll() {
    ensureNotDisposed('watchAll');
    return stream.watchAll();
  }

  Stream<Set<K>> watchKeys() {
    ensureNotDisposed('watchKeys');
    return stream.watchKeys();
  }

  // --- Collection-level Accessor<Map<K, T>, ()> delegation ---

  StatefulStream<Map<K, T>> watch({()? initialParameter, bool eager = false}) {
    ensureNotDisposed('watch');
    return accessor.watch(initialParameter: initialParameter, eager: eager);
  }

  Future<Map<K, T>> get(() parameter, {bool forceRefresh = false}) async {
    ensureNotDisposed('get');
    return accessor.get(parameter, forceRefresh: forceRefresh);
  }

  Future<Map<K, T>> refresh(() parameter) async {
    ensureNotDisposed('refresh');
    return accessor.refresh(parameter);
  }

  void trigger(() parameter, {bool forceRefresh = false}) {
    ensureNotDisposed('trigger');
    accessor.trigger(parameter, forceRefresh: forceRefresh);
  }

  StatefulData<Map<K, T>> current() => accessor.current();

  Map<K, T>? currentData() => accessor.currentData();

  // --- Single Key State Queries ---

  /// Returns the current state for [key] synchronously.
  StatefulData<T> currentKey(K key) => stream.stateOf(key);

  /// Returns the unwrapped data payload for [key] synchronously, or `null`.
  T? currentKeyData(K key) => stream.dataOf(key);

  // --- Invalidation & Cleanup ---

  /// Invalidates the cache entry, clears persistent storage, and resets state to [DataInitial] for [key].
  ///
  /// Removes the persisted entries of [key] for every parameter, including
  /// those written in earlier sessions. Requests for [key] still in flight
  /// are cancelled with a [TrooperCancelledException].
  void invalidateKey(K key) {
    if (isDisposed) return;
    queryQueue.cancelWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    final param = _lastParams.remove(key);
    if (param != null && telemetry.hasListeners) {
      telemetry.emit(
        CacheInvalidatedEvent(
          QueryKey.keyed(namespace, key: key, parameter: param),
        ),
      );
    }
    cache.removeWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    _purgeKeyStorage(key);
    stream.emitInitial(key);
  }

  /// Invalidates all keys belonging to this query family. Implements [Invalidatable].
  ///
  /// Removes every persisted entry of the namespace, including entries
  /// written in earlier sessions. Requests still in flight are cancelled
  /// with a [TrooperCancelledException].
  @override
  void invalidate() {
    if (isDisposed) return;
    queryQueue.cancelNamespace(namespace);
    for (final key in stream.activeKeys) {
      stream.emitInitial(key);
    }
    _lastParams.clear();
    cache.removeName(namespace);
    purgeStorage();
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
  ///
  /// Persisted entries of [key] are removed for every parameter, including
  /// those written in earlier sessions.
  Future<void> removeKey(K key) async {
    if (isDisposed) return;
    queryQueue.cancelWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    _lastParams.remove(key);
    cache.removeWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    _purgeKeyStorage(key);
    await stream.removeKey(key);
  }

  void _scheduleRelease(K key) {
    // Deferred, so a listener that re-subscribes right away keeps the key.
    scheduleMicrotask(() {
      if (_isDisposed || stream.isClosed || !stream.containsKey(key)) return;
      if (stream.hasKeyListeners(key) || stream.hasAggregateListeners) return;
      if (canReleaseKey(key)) releaseKeyState(key);
    });
  }

  /// Whether the in-memory state of [key] may be dropped now, see
  /// [releaseUnwatchedKeys]. Subclasses add their own conditions.
  @internal
  @mustCallSuper
  bool canReleaseKey(K key) => !queryQueue.hasOngoing(
    QueryKey.keyed(namespace, key: key, parameter: const ()),
  );

  /// Drops the in-memory state of [key] but keeps cache and storage.
  @internal
  @mustCallSuper
  void releaseKeyState(K key) {
    _lastParams.remove(key);
    unawaited(stream.removeKey(key));
  }

  /// Purges the persisted entries of [key] for every parameter, including
  /// those written in earlier sessions.
  void _purgeKeyStorage(K key) => purgeStorage(
    where: (storageKey) => QueryKey.storageKeyMatchesEntity(
      storageKey,
      namespace: namespace,
      entityKey: key,
    ),
  );

  /// Pauses cache expiration timers while backgrounded.
  @override
  void pause() {
    if (isDisposed) return;
    cache.pause();
  }

  /// Resumes cache expiration timers upon foregrounding.
  @override
  FutureOr<void> resume() {
    if (isDisposed) return null;
    cache.resume();
  }

  /// Clears all keys from this query family, purging cache, persisted
  /// entries of the namespace (also from earlier sessions), and the stream.
  Future<void> clearAll() async {
    if (isDisposed) return;
    _lastParams.clear();
    cache.removeName(namespace);
    purgeStorage();
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
