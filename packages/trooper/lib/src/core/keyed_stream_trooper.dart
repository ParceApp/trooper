import 'dart:async';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_trooper.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// Factory signature for creating an upstream [Stream] for entity [key].
typedef KeyedStreamFactory<K, T, P> =
    FutureOr<Stream<T>> Function(
      K key,
      P parameter,
      TrooperCancelToken cancelToken,
    );

/// A [KeyedTrooper] managing dynamic collections of reactive, push-based data streams partitioned by key [K].
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
///   namespace: 'chat_rooms',
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
    extends KeyedTrooper<K, T, P> {
  /// Creates a [KeyedStreamTrooper] with the specified [streamFactory].
  KeyedStreamTrooper({
    required super.namespace,
    required this.streamFactory,
    this.onConnect,
    this.onRefresh,
    this.onDisconnect,
    super.config,
    super.sideEffects,
    this.keepAlive = false,
    super.cache,
    super.queryQueue,
    super.telemetry,
    super.stream,
  });

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
    onDisconnect: onDisconnect,
    config: config,
    sideEffects: sideEffects,
    keepAlive: keepAlive,
    cache: cache,
    queryQueue: queryQueue,
    telemetry: telemetry,
    stream: streamManager,
  );

  /// Factory creating the upstream [Stream] for a given key.
  final KeyedStreamFactory<K, T, P> streamFactory;

  /// Optional hook invoked when connecting to the upstream stream for an entity key.
  final FutureOr<void> Function(
    K key,
    P parameter,
    TrooperCancelToken cancelToken,
  )?
  onConnect;

  /// Optional hook invoked when refreshing data for an entity key via [refreshKey] or [getKey].
  final FutureOr<void> Function(K key, P parameter)? onRefresh;

  /// Optional hook invoked when the upstream stream is disconnected via [disconnectKey].
  final FutureOr<void> Function(K key)? onDisconnect;

  /// If `true`, the upstream subscription stays active even when no active listeners remain.
  final bool keepAlive;

  final Map<K, StreamSubscription<T>> _subscriptions = {};
  final Map<K, TrooperCancelToken> _cancelTokens = {};
  final Map<K, int> _activeWatchers = {};
  final Map<K, T> _lastLoadedData = {};
  final Set<K> _pausedKeys = {};
  final Set<K> _connectingKeys = {};

  /// Whether an upstream subscription is currently active or connecting for [key].
  bool isConnectedKey(K key) =>
      _subscriptions.containsKey(key) || _connectingKeys.contains(key);

  /// Subscript operator to acquire a bound [Accessor] targeting [key].
  @override
  Accessor<T, P> operator [](K key) =>
      _KeyedStreamBoundAccessor<K, T, P>(this, key);

  /// Manually connects to the upstream stream for [key] using [parameter].
  Future<void> connectKey(K key, P parameter) async {
    final param = parameter;
    final currentParam = lastParamOf(key);

    // If already connected or connecting with the same parameter, keep existing connection
    if (isConnectedKey(key) && currentParam == param) {
      return;
    }

    _cleanupKey(key);

    final token = TrooperCancelToken();
    _cancelTokens[key] = token;
    _connectingKeys.add(key);

    final qKey = buildQueryKey(key, param);

    // Emit loading/refreshing according to stale policy
    final currentKeyDataVal = currentKeyData(key);
    if (currentKeyDataVal == null ||
        config.stalePolicy == StalePolicy.discardStaleOnRefresh) {
      stream.emitLoading(key);
    } else {
      final entry = cache.getEntry<T>(qKey);
      stream.emitRefreshing(key, currentKeyDataVal, metadata: entry?.metadata);
    }

    if (telemetry.hasListeners) {
      telemetry.emit(RequestStartedEvent(qKey));
    }
    runSideEffect(() => sideEffects?.onRequestStarted?.call(key, param));

    try {
      if (onConnect != null) {
        final connectResult = onConnect!(key, param, token);
        if (connectResult is Future) {
          await connectResult;
        }
        if (token.isCancelled) return;
      }

      await _resolveAndSubscribeKeyUpstream(key, param, token, qKey);
    } catch (error, stackTrace) {
      if (!token.isCancelled) {
        _handleKeyUpstreamError(key, error, stackTrace, qKey, param);
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
        _lastLoadedData[key] = data;
        if (config.hasCache) {
          cache.put(
            qKey,
            data,
            timeToLive: config.timeToLive,
            source: DataSource.network,
          );
        }
        final entry = config.hasCache ? cache.getEntry<T>(qKey) : null;
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

  /// Watches state updates for a single [key], managing automatic connection.
  StatefulStream<T> watchKey(K key, P parameter, {bool eager = true}) {
    if (eager && !isConnectedKey(key)) {
      connectKey(key, parameter).ignore();
    }

    final keyStream = stream.streamOf(key);

    return StatefulStream<T>(
      Stream.multi((controller) {
        _activeWatchers[key] = (_activeWatchers[key] ?? 0) + 1;
        final sub = keyStream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );

        controller.onCancel = () {
          sub.cancel();
          final count = (_activeWatchers[key] ?? 1) - 1;
          if (count <= 0) {
            _activeWatchers.remove(key);
            if (!keepAlive) {
              disconnectKey(key).ignore();
            }
          } else {
            _activeWatchers[key] = count;
          }
        };
      }),
      currentStateProvider: () => stream.stateOf(key),
    );
  }

  /// Reads the value for [key], returning immediately from cache if fresh,
  /// or waiting for the next upstream stream event.
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
    runSideEffect(() => sideEffects?.onData?.call(key, data, parameter));
    return data;
  }

  @override
  void invalidateKey(K key, [P? parameter]) {
    disconnectKey(key).ignore();
    super.invalidateKey(key, parameter);
  }

  @override
  void invalidate() {
    for (final key in stream.activeKeys) {
      disconnectKey(key).ignore();
    }
    super.invalidate();
  }

  @override
  Future<void> removeKey(K key, [P? parameter]) async {
    await disconnectKey(key);
    _lastLoadedData.remove(key);
    _activeWatchers.remove(key);
    _pausedKeys.remove(key);
    _connectingKeys.remove(key);
    await super.removeKey(key, parameter);
  }

  @override
  Future<void> clearAll() async {
    for (final key in List<K>.of(_subscriptions.keys)) {
      await disconnectKey(key);
    }
    _lastLoadedData.clear();
    _activeWatchers.clear();
    _pausedKeys.clear();
    _connectingKeys.clear();
    await super.clearAll();
  }

  @override
  void pause() {
    super.pause();
    _pausedKeys.addAll(_subscriptions.keys);
    for (final key in List<K>.of(_subscriptions.keys)) {
      disconnectKey(key).ignore();
    }
  }

  @override
  FutureOr<void> resume() {
    super.resume();
    final keysToResume = Set<K>.of(_pausedKeys);
    _pausedKeys.clear();
    for (final key in keysToResume) {
      if ((_activeWatchers[key] ?? 0) > 0 || keepAlive) {
        final param = lastParamOf(key);
        if (param != null) {
          connectKey(key, param).ignore();
        }
      }
    }
  }

  @override
  FutureOr<void> recover() {
    for (final key in stream.activeKeys) {
      final hasWatchers = (_activeWatchers[key] ?? 0) > 0 || keepAlive;
      final isErrored = stream.stateOf(key).isError;
      if ((!isConnectedKey(key) && hasWatchers) || isErrored) {
        final param = lastParamOf(key);
        if (param != null) {
          connectKey(key, param).ignore();
        }
      }
    }
  }

  @override
  FutureOr<void> didChangeDependencies() {
    final keysToReconnect = {
      for (final key in stream.activeKeys)
        if (isConnectedKey(key) || (_activeWatchers[key] ?? 0) > 0 || keepAlive)
          key: lastParamOf(key),
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
    for (final token in _cancelTokens.values) {
      token.cancel('KeyedStreamTrooper disposed');
    }
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _cancelTokens.clear();
    _subscriptions.clear();
    _lastLoadedData.clear();
    _activeWatchers.clear();
    _pausedKeys.clear();
    _connectingKeys.clear();
    await super.dispose();
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
