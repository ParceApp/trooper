import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/types/parameter.dart';

/// A Trooper managing dynamic collections of in-memory mutable local state partitioned by key [K].
///
/// Use subscript `operator []` or `.key(key)` to acquire a bound [Accessor] for a specific key.
///
/// Features:
/// - **Synchronous Per-Key Updates**: Mutate state via [setKey], [updateKey], [resetKey].
/// - **Bound Accessors**: Access single entries as standard [Accessor] instances.
/// - **Collection Streams**: Observe all entries via [watchAll], [watchKeys], and [currentDataMap].
/// - **Optional L2 Persistence**: Hydrates from and persists to [TrooperConfig.storage] via [codec].
///
/// ### Example:
/// ```dart
/// final drafts = KeyedLocalTrooper<String, String, ()>(
///   name: 'chat_drafts',
///   initialValue: '',
///   codec: TrooperCodec.string,
/// );
///
/// // Access single chat draft via subscript operator:
/// final chatDraft = drafts['room-101'];
/// print(chatDraft.currentData(())); // ''
///
/// // Mutate:
/// drafts.setKey('room-101', 'Hello world', ());
/// drafts.updateKey('room-101', (text) => '$text!', ());
/// drafts.resetKey('room-101', ());
///
/// // Watch all drafts:
/// drafts.watchAll().listen((map) {
///   print('Active drafts: ${map.length}');
/// });
/// ```
class KeyedLocalTrooper<K extends Object, T, P extends Parameter>
    with LifecycleAware
    implements Invalidatable, KeyedAccessor<K, T, P> {
  /// Creates a [KeyedLocalTrooper] with a static [initialValue] for all keys.
  KeyedLocalTrooper({
    required this.namespace,
    required T initialValue,
    TrooperConfig? config,
    CacheStore? cache,
    this.sideEffects,
    this.codec,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) : config = config ?? TrooperConfig.defaultConfig,
       _ownsCache = cache == null,
       _ownsQueryQueue = queryQueue == null,
       initialValueFactory = ((_) => initialValue),
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       stream = stream ?? KeyedStatefulStream<K, T>();

  /// Creates a [KeyedLocalTrooper] using a dynamic [initialValueFactory] per key.
  KeyedLocalTrooper.builder({
    required this.namespace,
    required this.initialValueFactory,
    TrooperConfig? config,
    CacheStore? cache,
    this.sideEffects,
    this.codec,
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

  /// Logical family name for this collection of local state entries.
  final String namespace;

  /// Function generating baseline initial value for any given key.
  final T Function(K key) initialValueFactory;

  /// Optional codec for persistent L2 storage synchronization.
  final TrooperCodec<T>? codec;

  /// Optional side-effect callbacks for lifecycle hooks.
  final KeyedTrooperSideEffects<K, T, P>? sideEffects;

  /// Configuration defining TTL and storage backend.
  final TrooperConfig config;

  /// In-memory cache store.
  final CacheStore cache;

  /// Concurrency queryQueue.
  final TrooperQueryQueue queryQueue;

  /// Telemetry hub.
  final TelemetryHub telemetry;

  /// Replay-enabled keyed stream manager.
  final KeyedStatefulStream<K, T> stream;

  final Set<K> _hydratedKeys = {};
  final Map<K, P> _lastParams = {};
  bool _isDisposed = false;

  /// Whether [key] has been hydrated from L2 storage.
  bool isHydratedKey(K key) => _hydratedKeys.contains(key);

  /// Returns a read-only [KeyedAccessor] facade over this keyed trooper.
  late final KeyedAccessor<K, T, P> accessor = KeyedTrooperAccessor<K, T, P>(
    accessorFactory: (k) => this[k],
    stream: stream,
    onInvalidate: invalidate,
    onInvalidateKey: invalidateKey,
  );

  /// Returns the baseline initial value for [key].
  T initialValueOf(K key) => initialValueFactory(key);

  /// Convenient subscript operator to acquire a bound [Accessor] for [key].
  @override
  Accessor<T, P> operator [](K key) =>
      _KeyedLocalBoundAccessor<K, T, P>(this, key);

  /// Returns a bound read-only [Accessor] scoped to entity [key].
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
  void trigger(() parameter, {bool forceRefresh = false}) =>
      accessor.trigger(parameter, forceRefresh: forceRefresh);

  @override
  Future<Map<K, T>> refresh(() parameter) =>
      accessor.refresh(parameter);

  @override
  StatefulData<Map<K, T>> current(() parameter) =>
      accessor.current(parameter);

  @override
  Map<K, T>? currentData(() parameter) =>
      accessor.currentData(parameter);

  /// Returns the most recent parameter used for [key], or `null` if none.
  P? lastParamOf(K key) => _lastParams[key];

  /// Builds a [QueryKey] targeting [key].
  @protected
  QueryKey buildQueryKey(K key, P parameter) {
    _lastParams[key] = parameter;
    return QueryKey.keyed(
      namespace,
      key: key as Object,
      parameter: parameter,
    );
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

  /// Updates the local state for [key] to [value] and returns the updated value.
  ///
  /// Emits [DataLoaded] on [stream], updates L1 cache, and asynchronously persists
  /// to L2 storage if configured.
  T setKey(K key, T value, P parameter) {
    final qKey = buildQueryKey(key, parameter);

    cache.put(
      qKey,
      value,
      timeToLive: config.timeToLive,
      source: DataSource.local,
    );

    final entry = cache.getEntry<T>(qKey);
    stream.emitData(key, value, metadata: entry?.metadata);

    if (telemetry.hasListeners) {
      telemetry.emit(
        RequestCompletedEvent(
          qKey,
          duration: Duration.zero,
          source: DataSource.local,
        ),
      );
    }

    _runSideEffect(() => sideEffects?.onData?.call(key, value, parameter));

    final storage = config.storage;
    final currentCodec = codec;
    if (storage != null && currentCodec != null) {
      try {
        final serialized = currentCodec.encode(value);
        storage.write(qKey.storageKey, serialized).ignore();
      } catch (_) {
        // Non-critical persistence failure
      }
    }
    return value;
  }

  /// Updates the state for [key] by applying [transform] to its current value
  /// and returns the updated value.
  T updateKey(K key, T Function(T current) transform, P parameter) {
    final current = currentKeyData(key) ?? initialValueFactory(key);
    final updated = transform(current);
    setKey(key, updated, parameter);
    return updated;
  }

  /// Resets the state for [key] back to its initial value, deletes persistent storage,
  /// and returns the initial value.
  T resetKey(K key, P parameter) {
    final initial = initialValueFactory(key);
    setKey(key, initial, parameter);

    final storage = config.storage;
    if (storage != null) {
      final qKey = buildQueryKey(key, parameter);
      storage.delete(qKey.storageKey).ignore();
    }
    return initial;
  }

  /// Resets all currently tracked keys back to their initial values.
  void resetAll() {
    for (final key in activeKeys) {
      final param = _lastParams[key] ?? (const () is P ? const () as P : null);
      if (param != null) {
        resetKey(key, param);
      }
    }
  }

  /// Reads the value for [key], returning cached data if fresh, hydrating from L2
  /// storage if configured, or falling back to [initialValueFactory].
  Future<T> getKey(K key, P parameter, {bool forceRefresh = false}) async {
    final qKey = buildQueryKey(key, parameter);

    // 1. Check L1 Memory Cache
    if (!forceRefresh && config.hasCache) {
      final entry = cache.getEntry<T>(qKey);
      if (entry != null && entry.isFresh) {
        if (telemetry.hasListeners) {
          telemetry.emit(
            CacheHitEvent(qKey, isFresh: true, metadata: entry.metadata),
          );
        }
        stream.emitData(key, entry.data, metadata: entry.metadata);
        return entry.data;
      }
    }

    // 2. Hydrate from L2 Storage if configured and not yet hydrated
    if (!_hydratedKeys.contains(key) &&
        config.storage != null &&
        codec != null) {
      final storage = config.storage!;
      final currentCodec = codec!;

      try {
        final serialized = await storage.read(qKey.storageKey);
        if (serialized != null) {
          final decoded = currentCodec.decode(serialized);
          cache.put(
            qKey,
            decoded,
            timeToLive: config.timeToLive,
            source: DataSource.storage,
          );
          final entry = cache.getEntry<T>(qKey);
          if (telemetry.hasListeners) {
            telemetry.emit(
              CacheHitEvent(qKey, isFresh: true, metadata: entry?.metadata),
            );
          }
          stream.emitData(key, decoded, metadata: entry?.metadata);
          _runSideEffect(() => sideEffects?.onData?.call(key, decoded, parameter));
          _hydratedKeys.add(key);
          return decoded;
        }
      } catch (_) {
        storage.delete(qKey.storageKey).ignore();
      }

      _hydratedKeys.add(key);
    }

    // 3. Fallback to stream value or initial baseline
    if (!stream.containsKey(key)) {
      final initial = initialValueFactory(key);
      cache.put(
        qKey,
        initial,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
      final entry = cache.getEntry<T>(qKey);
      stream.emitData(key, initial, metadata: entry?.metadata);
      return initial;
    }

    return currentKeyData(key) ?? initialValueFactory(key);
  }

  /// Refreshes the value for [key] by re-reading from storage.
  Future<T> refreshKey(K key, P parameter) =>
      getKey(key, parameter, forceRefresh: true);

  /// Triggers reading or hydrating data for [key] without awaiting the result.
  void triggerKey(K key, P parameter, {bool forceRefresh = false}) {
    getKey(key, parameter, forceRefresh: forceRefresh).ignore();
  }

  /// Watches state updates for a single [key].
  StatefulStream<T> watchKey(K key, P parameter, {bool eager = true}) {
    if (!stream.containsKey(key)) {
      final initial = initialValueFactory(key);
      final qKey = buildQueryKey(key, parameter);
      cache.put(
        qKey,
        initial,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
      final entry = cache.getEntry<T>(qKey);
      stream.emitData(key, initial, metadata: entry?.metadata);
    }

    if (eager &&
        !_hydratedKeys.contains(key) &&
        config.storage != null &&
        codec != null) {
      getKey(key, parameter).ignore();
    }

    return stream.streamOf(key);
  }

  /// Returns the current state for [key] synchronously.
  StatefulData<T> currentKeyState(K key) {
    if (stream.containsKey(key)) {
      return stream.stateOf(key);
    }
    return DataLoaded(
      initialValueFactory(key),
      metadata: DataMetadata.now(source: DataSource.local),
    );
  }

  /// Returns the unwrapped data payload for [key] if available.
  T? currentKeyData(K key) => stream.containsKey(key)
      ? stream.stateOf(key).dataOrNull
      : initialValueFactory(key);

  /// Watches aggregate state updates across all tracked entity keys.
  @override
  Stream<Map<K, StatefulData<T>>> watchAll() => stream.watchAll();

  /// Watches updates to the set of currently tracked keys.
  @override
  Stream<Set<K>> watchKeys() => stream.watchKeys();

  /// Returns an unmodifiable map of all currently loaded data payloads.
  @override
  Map<K, T> get currentDataMap => stream.currentDataMap;

  /// Returns the set of currently active keys.
  @override
  Set<K> get activeKeys => stream.activeKeys;

  /// Returns the count of currently active keys.
  @override
  int get count => stream.count;

  /// Removes [key] from the stream, cache, and persistent storage.
  Future<void> removeKey(K key) async {
    final param = _lastParams.remove(key) ?? (const () is P ? const () as P : null);
    _hydratedKeys.remove(key);
    cache.removeWhere(
      (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
    );
    await stream.removeKey(key);

    if (param != null) {
      final storage = config.storage;
      if (storage != null) {
        final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
        storage.delete(qKey.storageKey).ignore();
      }
    }
  }

  /// Clears all keys from the stream and cache.
  Future<void> clearAll() async {
    _lastParams.clear();
    _hydratedKeys.clear();
    cache.removeName(namespace);
    await stream.clearAll();
  }

  /// Invalidates cached data, clears persistent storage, and resets state to [DataInitial] for [key].
  @override
  void invalidateKey(K key) {
    final param = _lastParams.remove(key) ?? (const () is P ? const () as P : null);
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
        (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
      );
    }
    _hydratedKeys.remove(key);
    stream.emitInitial(key);
  }

  /// Invalidates all keys belonging to this query family. Implements [Invalidatable].
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
    _hydratedKeys.clear();
    cache.removeName(namespace);
    if (telemetry.hasListeners) {
      telemetry.emit(CacheInvalidatedEvent(QueryKey(namespace, const ())));
    }
  }

  /// Purges cache and resets all active keys back to baseline via [initialValueFactory].
  @override
  FutureOr<void> didChangeDependencies() {
    invalidate();
    if (config.refreshAfterChangeDependencies) {
      resetAll();
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _lastParams.clear();
    _hydratedKeys.clear();
    await stream.dispose();
    if (_ownsQueryQueue) {
      await queryQueue.dispose();
    }
    if (_ownsCache) {
      await cache.dispose();
    }
  }
}

class _KeyedLocalBoundAccessor<K extends Object, T, P extends Parameter>
    implements Accessor<T, P> {
  const _KeyedLocalBoundAccessor(this._parent, this._key);
  final KeyedLocalTrooper<K, T, P> _parent;
  final K _key;

  @override
  StatefulStream<T> watch(P parameter, {bool eager = true}) =>
      _parent.watchKey(_key, parameter, eager: eager);

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) =>
      _parent.getKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) =>
      _parent.triggerKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  Future<T> refresh(P parameter) =>
      _parent.refreshKey(_key, parameter);

  @override
  StatefulData<T> current(P parameter) => _parent.currentKeyState(_key);

  @override
  T? currentData(P parameter) => _parent.currentKeyData(_key);

  @override
  void invalidate() => _parent.invalidateKey(_key);
}

/// Convenience extension for parameterless [KeyedLocalTrooper] instances where `P` is `()`.
extension ParameterlessKeyedLocalTrooper<K extends Object, T>
    on KeyedLocalTrooper<K, T, ()> {
  /// Reads or hydrates data for [key] without requiring an explicit `()` parameter.
  Future<T> getKey(K key, {bool forceRefresh = false}) =>
      this.getKey(key, const (), forceRefresh: forceRefresh);

  /// Sets data for [key] without requiring an explicit `()` parameter.
  T setKey(K key, T value) => this.setKey(key, value, const ());

  /// Updates state for [key] without requiring an explicit `()` parameter.
  T updateKey(K key, T Function(T current) transform) =>
      this.updateKey(key, transform, const ());

  /// Resets state for [key] without requiring an explicit `()` parameter.
  T resetKey(K key) => this.resetKey(key, const ());

  /// Refreshes state for [key] without requiring an explicit `()` parameter.
  Future<T> refreshKey(K key) => this.refreshKey(key, const ());

  /// Triggers reading or hydrating data for [key] without requiring an explicit `()` parameter.
  void triggerKey(K key, {bool forceRefresh = false}) =>
      this.triggerKey(key, const (), forceRefresh: forceRefresh);

  /// Watches state updates for a single [key] without requiring an explicit `()` parameter.
  StatefulStream<T> watchKey(K key, {bool eager = true}) =>
      this.watchKey(key, const (), eager: eager);
}
