import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// Function signature for creating an upstream push stream for a specific entity [key].
///
/// Can return a [Stream] directly or a [Future] completing with a [Stream]
/// for asynchronous connection setup, authentication, or room joining.
typedef KeyedStreamFactory<K, T, P extends Parameter> =
    FutureOr<Stream<T>> Function(
      K key,
      P parameter,
      TrooperCancelToken cancelToken,
    );

/// A Trooper managing dynamic collections of reactive, push-based data streams partitioned by key [K].
///
/// Use subscript `operator []` or `.key(key)` to acquire a bound [Accessor] for a specific entity.
///
/// Features:
/// - **Per-Key Push Streams**: Independently subscribes to upstream streams by key.
/// - **Bound Accessors**: Access single entries as standard [Accessor] instances.
/// - **Automatic Lifecycle**: Connects to upstream per-key streams on-demand and
///   disconnects when the last listener for that key unsubscribes (unless [keepAlive] is true).
/// - **Collection Observables**: Observe all entries via [watchAll], [watchKeys], and [currentDataMap].
/// - **Bi-Directional Support**: Optional [onConnect] and [onRefresh] hooks to send commands per key.
/// - **L1 Cache Integration**: Incoming live stream items populate the L1 cache.
///
/// ### Example:
/// ```dart
/// final roomChat = KeyedStreamTrooper<String, ChatMessage, ()>(
///   name: 'chat_rooms',
///   streamFactory: (roomId, _, cancelToken) => webSocket.joinRoom(roomId),
///   onRefresh: (roomId, _) => webSocket.send({'cmd': 'history', 'room': roomId}),
/// );
///
/// // Access single room stream via subscript operator:
/// final room101 = roomChat['room-101'];
/// room101.watch(()).dataStream.listen((message) {
///   print('New message in room 101: ${message.text}');
/// });
///
/// // Watch all active chat rooms:
/// roomChat.watchAll().listen((roomStates) {
///   print('Active rooms: ${roomStates.keys}');
/// });
/// ```
class KeyedStreamTrooper<K extends Object, T, P extends Parameter>
    with LifecycleAware
    implements Invalidatable, KeyedAccessor<K, T, P> {
  /// Creates a [KeyedStreamTrooper] with the specified [streamFactory].
  KeyedStreamTrooper({
    required this.namespace,
    required this.streamFactory,
    this.onConnect,
    this.onRefresh,
    this.onDisconnect,
    TrooperConfig? config,
    this.sideEffects,
    this.keepAlive = false,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? stream,
  }) : _ownsCache = cache == null,
       _ownsQueryQueue = queryQueue == null,
       config = config ?? .defaultConfig,
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       stream = stream ?? KeyedStatefulStream<K, T>();

  /// Factory method for parameterless keyed streams.
  static KeyedStreamTrooper<K, T, ()> fromStream<K extends Object, T>({
    required String namespace,
    required FutureOr<Stream<T>> Function(K key) stream,
    FutureOr<void> Function(K key, TrooperCancelToken cancelToken)? onConnect,
    FutureOr<void> Function(K key)? onRefresh,
    FutureOr<void> Function(K key)? onDisconnect,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, ()>? sideEffects,
    bool keepAlive = false,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    KeyedStatefulStream<K, T>? streamManager,
  }) => KeyedStreamTrooper<K, T, ()>(
    namespace: namespace,
    streamFactory: (key, _, _) => stream(key),
    onConnect: onConnect != null
        ? (key, _, token) => onConnect(key, token)
        : null,
    onRefresh: onRefresh != null ? (key, _) => onRefresh(key) : null,
    config: config,
    sideEffects: sideEffects,
    keepAlive: keepAlive,
    cache: cache,
    queryQueue: queryQueue,
    telemetry: telemetry,
    stream: streamManager,
  );

  final bool _ownsCache;
  final bool _ownsQueryQueue;

  /// Logical family name for this collection of stream resources.
  final String namespace;

  /// Factory creating the upstream [Stream] for a given key.
  final KeyedStreamFactory<K, T, P> streamFactory;

  /// Optional hook invoked when connecting to the upstream stream for an entity key.
  ///
  /// Useful for sending initial subscription frames, authentication, or joining rooms.
  final FutureOr<void> Function(
    K key,
    P parameter,
    TrooperCancelToken cancelToken,
  )?
  onConnect;

  /// Optional hook invoked when refreshing data for an entity key via [refreshKey] or [getKey].
  ///
  /// Useful for requesting immediate snapshots or polling fresh data over an active socket.
  final FutureOr<void> Function(K key, P parameter)? onRefresh;

  /// Optional hook invoked when the upstream stream for an entity key is disconnected via [disconnect].
  ///
  /// Useful for sending unsubscribe frames or cleaning up resources on the server side.
  final FutureOr<void> Function(K key)? onDisconnect;

  /// Configuration defining TTL and stale policy.
  final TrooperConfig config;

  /// Optional side-effect callbacks for lifecycle hooks.
  final KeyedTrooperSideEffects<K, T, P>? sideEffects;

  /// In-memory L1 cache store.
  final CacheStore cache;

  /// Concurrency and request queryQueue.
  final TrooperQueryQueue queryQueue;

  /// Telemetry hub for diagnostic events.
  final TelemetryHub telemetry;

  /// Replay-enabled keyed stream manager.
  final KeyedStatefulStream<K, T> stream;

  /// If `true`, per-key upstream subscriptions stay active even when no watchers remain.
  /// If `false` (default), subscriptions cancel when the last watcher for that key cancels.
  final bool keepAlive;

  final Map<K, StreamSubscription<T>> _subscriptions = {};
  final Map<K, TrooperCancelToken> _cancelTokens = {};
  final Map<K, P> _currentParams = {};
  final Map<K, T> _lastLoadedData = {};
  final Map<K, int> _activeWatchers = {};
  final Set<K> _pausedKeys = {};
  final Set<K> _connectingKeys = {};
  bool _isDisposed = false;

  /// Returns a read-only [KeyedAccessor] facade over this keyed stream trooper.
  late final KeyedAccessor<K, T, P> accessor = KeyedTrooperAccessor<K, T, P>(
    accessorFactory: (k) => this[k],
    stream: stream,
    onInvalidate: invalidate,
    onInvalidateKey: invalidateKey,
  );

  /// Convenient subscript operator to acquire a bound [Accessor] for [key].
  @override
  Accessor<T, P> operator [](K key) =>
      _KeyedStreamBoundAccessor<K, T, P>(this, key);

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
  void trigger(() parameter, {bool forceRefresh = false}) =>
      accessor.trigger(parameter, forceRefresh: forceRefresh);

  @override
  Future<Map<K, T>> refresh(() parameter) => accessor.refresh(parameter);

  @override
  StatefulData<Map<K, T>> current(() parameter) => accessor.current(parameter);

  @override
  Map<K, T>? currentData(() parameter) => accessor.currentData(parameter);

  /// Builds a [QueryKey] targeting [key].
  @protected
  QueryKey buildQueryKey(K key, P parameter) {
    _currentParams[key] = parameter;
    return QueryKey.keyed(namespace, key: key as Object, parameter: parameter);
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

  /// Whether an upstream subscription is currently active or connecting for [key].
  bool isConnectedKey(K key) =>
      _subscriptions.containsKey(key) || _connectingKeys.contains(key);

  /// Manually connects to the upstream stream for [key] using [parameter].
  Future<void> connectKey(K key, P parameter) async {
    // If already connected or connecting with identical parameter, keep existing connection
    if ((_subscriptions.containsKey(key) || _connectingKeys.contains(key)) &&
        _currentParams[key] == parameter) {
      return;
    }

    _cleanupKey(key);
    _currentParams[key] = parameter;

    final token = TrooperCancelToken();
    _cancelTokens[key] = token;
    final qKey = buildQueryKey(key, parameter);

    // Emit loading if no current data or if stale policy discards stale data,
    // otherwise emit refreshing (SWR).
    final current = currentKeyData(key);
    if (current != null &&
        config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
      stream.emitRefreshing(key, current);
    } else {
      stream.emitLoading(key);
    }

    if (telemetry.hasListeners) {
      telemetry.emit(RequestStartedEvent(qKey));
    }
    runSideEffect(() => sideEffects?.onRequestStarted?.call(key, parameter));

    try {
      _connectingKeys.add(key);
      if (onConnect != null) {
        final connectResult = onConnect!(key, parameter, token);
        if (connectResult is Future) {
          await connectResult;
        }
        if (token.isCancelled) return;
      }

      await _resolveAndSubscribeKeyUpstream(key, parameter, token, qKey);
    } catch (error, stackTrace) {
      if (!token.isCancelled) {
        _handleKeyUpstreamError(key, error, stackTrace, qKey, parameter);
      }
    } finally {
      if (_cancelTokens[key] == token) {
        _connectingKeys.remove(key);
      }
    }
  }

  Future<void> _resolveAndSubscribeKeyUpstream(
    K key,
    P param,
    TrooperCancelToken token,
    QueryKey qKey,
  ) async {
    final upstreamOrFuture = streamFactory(key, param, token);
    final Stream<T> upstream;
    if (upstreamOrFuture is Future<Stream<T>>) {
      upstream = await upstreamOrFuture;
    } else {
      upstream = upstreamOrFuture;
    }
    if (token.isCancelled) return;
    _subscribeKeyUpstream(key, upstream, qKey, param);
  }

  void _subscribeKeyUpstream(
    K key,
    Stream<T> upstream,
    QueryKey qKey,
    P param,
  ) {
    _subscriptions[key] = upstream.listen(
      (data) {
        if (sideEffects != null &&
            sideEffects?.transformRequestResult != null) {
          runSideEffect(() async {
            T transformation = await sideEffects!.transformRequestResult!.call(
              key,
              data,
              param,
            );
            data = transformation;
          });
        }
        _lastLoadedData[key] = data;
        cache.put(
          qKey,
          data,
          timeToLive: config.timeToLive,
          source: DataSource.network,
        );
        final entry = cache.getEntry<T>(qKey);
        stream.emitData(key, data, metadata: entry?.metadata);

        if (telemetry.hasListeners) {
          telemetry.emit(
            RequestCompletedEvent(
              qKey,
              duration: Duration.zero,
              source: DataSource.network,
            ),
          );
        }
        runSideEffect(() => sideEffects?.onData?.call(key, data, param));
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleKeyUpstreamError(key, error, stackTrace, qKey, param);
      },
      onDone: () {
        _subscriptions.remove(key);
        _cancelTokens.remove(key);
      },
      cancelOnError: false,
    );
  }

  void _handleKeyUpstreamError(
    K key,
    Object error,
    StackTrace stackTrace,
    QueryKey qKey,
    P param,
  ) {
    stream.emitError(
      key,
      error,
      stackTrace: stackTrace,
      staleData: _lastLoadedData[key] ?? currentKeyData(key),
    );
    if (telemetry.hasListeners) {
      telemetry.emit(
        RequestErrorEvent(
          qKey,
          error: error,
          duration: Duration.zero,
          stackTrace: stackTrace,
        ),
      );
    }
    runSideEffect(
      () => sideEffects?.onError?.call(key, error, stackTrace, param),
    );
  }

  void _cleanupKey(K key) {
    _connectingKeys.remove(key);
    _cancelTokens.remove(key)?.cancel('Stream reconnected');
    _subscriptions.remove(key)?.cancel().ignore();
  }

  /// Disconnects the upstream stream subscription for [key].
  Future<void> disconnectKey(K key) async {
    onDisconnect?.call(key);
    _connectingKeys.remove(key);
    _cancelTokens.remove(key)?.cancel('Stream disconnected');
    final sub = _subscriptions.remove(key);
    await sub?.cancel();
  }

  /// Watches state updates for a single [key].
  StatefulStream<T> watchKey(K key, P parameter, {bool eager = true}) {
    if (eager && !isConnectedKey(key)) {
      connectKey(key, parameter).ignore();
    }

    final keyStream = stream.streamOf(key);

    return StatefulStream<T>(
      Stream<StatefulData<T>>.multi((listener) {
        _activeWatchers[key] = (_activeWatchers[key] ?? 0) + 1;
        final sub = keyStream.listen(
          listener.addSync,
          onError: listener.addError,
          onDone: listener.close,
        );

        listener.onCancel = () async {
          await sub.cancel();
          final count = (_activeWatchers[key] ?? 1) - 1;
          if (count <= 0) {
            _activeWatchers.remove(key);
            if (!keepAlive) {
              await disconnectKey(key);
            }
          } else {
            _activeWatchers[key] = count;
          }
        };
      }, isBroadcast: true),
      currentStateProvider: () => currentKey(key),
      rawBroadcastStream: keyStream.rawBroadcastStream,
    );
  }

  /// Reads the value for [key], awaiting the stream if not yet cached.
  Future<T> getKey(K key, P parameter, {bool forceRefresh = false}) async {
    final qKey = buildQueryKey(key, parameter);

    if (!forceRefresh && config.hasCache) {
      final cached = cache.get<T>(qKey);
      if (cached != null && !cache.isStale(qKey)) {
        return cached;
      }
    }

    final keyStream = stream.streamOf(key);
    final streamToAwait = forceRefresh ? keyStream.skipCurrent() : keyStream;

    final stateFuture = streamToAwait.firstWhere(
      (s) => s is DataLoaded<T> || s is DataError<T>,
      orElse: () => throw const TrooperCancelledException(
        message: 'Stream closed before data was received',
      ),
    );

    final shouldDisconnectAfterRead =
        (_activeWatchers[key] ?? 0) == 0 && !keepAlive;

    try {
      if (forceRefresh && onRefresh != null) {
        if (!isConnectedKey(key)) {
          await connectKey(key, parameter);
        }
        await onRefresh!(key, parameter);
      } else if (forceRefresh || !isConnectedKey(key)) {
        await connectKey(key, parameter);
      }

      final state = await stateFuture;

      if (state is DataLoaded<T>) {
        return state.data;
      }

      final errorState = state as DataError<T>;
      Error.throwWithStackTrace(
        errorState.error,
        errorState.stackTrace ?? StackTrace.current,
      );
    } finally {
      if (shouldDisconnectAfterRead) {
        await disconnectKey(key);
      }
    }
  }

  /// Triggers reading or hydrating data for [key] without awaiting the result.
  void triggerKey(K key, P parameter, {bool forceRefresh = false}) {
    getKey(key, parameter, forceRefresh: forceRefresh).ignore();
  }

  /// Refreshes the value for [key] by reconnecting and awaiting the next fresh event.
  Future<T> refreshKey(K key, P parameter) =>
      getKey(key, parameter, forceRefresh: true);

  /// Returns the current state for [key] synchronously.
  StatefulData<T> currentKey(K key) => stream.stateOf(key);

  /// Returns the unwrapped data payload for [key] if available.
  T? currentKeyData(K key) => stream.dataOf(key);

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

  /// Removes [key] from the stream, cache, and disconnects its upstream.
  Future<void> removeKey(K key) async {
    final param =
        _currentParams.remove(key) ?? (const () is P ? const () as P : null);

    await disconnectKey(key);
    _lastLoadedData.remove(key);
    _activeWatchers.remove(key);
    _pausedKeys.remove(key);
    _connectingKeys.remove(key);
    if (param != null) {
      final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
      cache.remove(qKey);
    } else {
      cache.removeWhere(
        (k) => k.matchesNameAndKey(name: namespace, entityKey: key),
      );
    }
    await stream.removeKey(key);
  }

  /// Disconnects all active key subscriptions.
  Future<void> disconnectAll() async {
    final keys = {..._subscriptions.keys, ..._connectingKeys};
    for (final key in keys) {
      await disconnectKey(key);
    }
  }

  /// Clears all keys from the stream and cache.
  Future<void> clearAll() async {
    await disconnectAll();
    _lastLoadedData.clear();
    _activeWatchers.clear();
    _currentParams.clear();
    _pausedKeys.clear();
    _connectingKeys.clear();
    cache.removeName(namespace);
    await stream.clearAll();
  }

  /// Invalidates cached data, disconnects upstream, clears persistent storage, and resets state to [DataInitial] for [key].
  @override
  void invalidateKey(K key) {
    disconnectKey(key).ignore();
    final param =
        _currentParams.remove(key) ?? (const () is P ? const () as P : null);
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
    stream.emitInitial(key);
  }

  /// Invalidates all keys belonging to this query family. Implements [Invalidatable].
  @override
  void invalidate() {
    final storage = config.storage;
    for (final key in stream.activeKeys) {
      disconnectKey(key).ignore();
      final param =
          _currentParams[key] ?? (const () is P ? const () as P : null);
      if (param != null) {
        final qKey = QueryKey.keyed(namespace, key: key, parameter: param);
        cache.remove(qKey);
        if (storage != null) {
          storage.delete(qKey.storageKey).ignore();
        }
      }
      stream.emitInitial(key);
    }
    _currentParams.clear();
    cache.removeName(namespace);
    if (telemetry.hasListeners) {
      telemetry.emit(CacheInvalidatedEvent(QueryKey(namespace, const ())));
    }
  }

  /// Temporarily disconnects active upstreams across all keys (e.g. app in background).
  @override
  Future<void> pause() async {
    cache.pause();
    final connected = _subscriptions.keys.toList();
    _pausedKeys.addAll(connected);
    for (final key in connected) {
      await disconnectKey(key);
    }
  }

  /// Reconnects previously paused keys if they have active watchers or keepAlive.
  @override
  FutureOr<void> resume() {
    cache.resume();
    final keysToResume = _pausedKeys.toList();
    _pausedKeys.clear();
    for (final key in keysToResume) {
      if ((_activeWatchers[key] ?? 0) > 0 || keepAlive) {
        final param =
            _currentParams[key] ?? (const () is P ? const () as P : null);
        if (param != null) {
          connectKey(key, param).ignore();
        }
      }
    }
  }

  /// Reconnects disconnected or errored keys that have active watchers or keepAlive.
  @override
  FutureOr<void> recover() {
    for (final key in stream.activeKeys) {
      final hasWatchers = (_activeWatchers[key] ?? 0) > 0 || keepAlive;
      final isErrored = stream.stateOf(key).isError;
      if ((!isConnectedKey(key) && hasWatchers) || isErrored) {
        final param =
            _currentParams[key] ?? (const () is P ? const () as P : null);
        if (param != null) {
          connectKey(key, param).ignore();
        }
      }
    }
  }

  /// Purges cache and reconnects all actively watched keys.
  @override
  FutureOr<void> didChangeDependencies() {
    final keysToReconnect = {
      for (final key in stream.activeKeys)
        if (isConnectedKey(key) || (_activeWatchers[key] ?? 0) > 0 || keepAlive)
          key: _currentParams[key] ?? (const () is P ? const () as P : null),
    };
    invalidate();
    if (config.refreshAfterChangeDependencies) {
      for (final entry in keysToReconnect.entries) {
        if (entry.value != null) {
          connectKey(entry.key, entry.value!).ignore();
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await disconnectAll();
    _lastLoadedData.clear();
    _activeWatchers.clear();
    _currentParams.clear();
    _pausedKeys.clear();
    _connectingKeys.clear();
    _cancelTokens.clear();
    _subscriptions.clear();
    await stream.dispose();
    if (_ownsQueryQueue) {
      await queryQueue.dispose();
    }
    if (_ownsCache) {
      await cache.dispose();
    }
  }
}

class _KeyedStreamBoundAccessor<K extends Object, T, P extends Parameter>
    implements Accessor<T, P> {
  const _KeyedStreamBoundAccessor(this._parent, this._key);
  final KeyedStreamTrooper<K, T, P> _parent;
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
  Future<T> refresh(P parameter) => _parent.refreshKey(_key, parameter);

  @override
  StatefulData<T> current(P parameter) => _parent.currentKey(_key);

  @override
  T? currentData(P parameter) => _parent.currentKeyData(_key);

  @override
  void invalidate() => _parent.invalidateKey(_key);
}

/// Convenience extension for parameterless [KeyedStreamTrooper] instances where `P` is `()`.
extension ParameterlessKeyedStreamTrooper<K extends Object, T>
    on KeyedStreamTrooper<K, T, ()> {
  /// Connects to the upstream stream for [key] without requiring an explicit `()` parameter.
  Future<void> connectKey(K key) => this.connectKey(key, const ());

  /// Reads the value for [key] without requiring an explicit `()` parameter.
  Future<T> getKey(K key, {bool forceRefresh = false}) =>
      this.getKey(key, const (), forceRefresh: forceRefresh);

  /// Refreshes the value for [key] without requiring an explicit `()` parameter.
  Future<T> refreshKey(K key) => this.refreshKey(key, const ());

  /// Triggers a fetch of [key] without requiring an explicit `()` parameter.
  void triggerKey(K key, {bool forceRefresh = false}) =>
      this.triggerKey(key, const (), forceRefresh: forceRefresh);

  /// Watches state updates for [key] without requiring an explicit `()` parameter.
  StatefulStream<T> watchKey(K key, {bool eager = true}) =>
      this.watchKey(key, const (), eager: eager);

  /// Manually sets data for [key] without requiring an explicit `()` parameter.
  T setKey(K key, T data) => this.setKey(key, data, const ());
}
