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
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/storage/cache_entry.dart';
import 'package:trooper/src/storage/storage_envelope.dart';
import 'package:trooper/src/storage/cache_store.dart';
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
/// Use subscript `operator []` to acquire a bound [Accessor] for a specific entity.
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
final class KeyedStreamTrooper<K extends Object, T, P extends Parameter>
    extends KeyedTrooper<K, T, P> {
  /// Creates a [KeyedStreamTrooper] with the specified [streamFactory].
  KeyedStreamTrooper({
    required super.namespace,
    required this.streamFactory,
    this.codec,
    this.onConnect,
    this.onRefresh,
    this.onDisconnect,
    super.config,
    super.sideEffects,
    this.keepAlive = false,
    super.cache,
    super.queryQueue,
    super.telemetry,
    super.releaseUnwatchedKeys,
  });

  /// Factory method for parameterless keyed streams.
  static KeyedStreamTrooper<K, T, ()> fromStream<K extends Object, T>({
    required String namespace,
    required FutureOr<Stream<T>> Function(K key) stream,
    TrooperCodec<T>? codec,
    FutureOr<void> Function(K key, TrooperCancelToken cancelToken)? onConnect,
    FutureOr<void> Function(K key)? onRefresh,
    FutureOr<void> Function(K key)? onDisconnect,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, ()>? sideEffects,
    bool keepAlive = false,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    bool releaseUnwatchedKeys = false,
  }) => KeyedStreamTrooper<K, T, ()>(
    namespace: namespace,
    streamFactory: (key, _, _) => stream(key),
    codec: codec,
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
    releaseUnwatchedKeys: releaseUnwatchedKeys,
  );

  /// Factory creating the upstream [Stream] for a given key.
  final KeyedStreamFactory<K, T, P> streamFactory;

  /// Optional codec for L2 storage serialization and hydration.
  final TrooperCodec<T>? codec;

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
    if (currentKeyDataVal != null &&
        config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
      final entry = cache.getEntry<T>(qKey);
      stream.emitRefreshing(key, currentKeyDataVal, metadata: entry?.metadata);
    } else if (currentKeyDataVal == null &&
        config.hasCache &&
        storageFor(qKey) != null &&
        codec != null) {
      final storage = storageFor(qKey)!;
      final currentCodec = codec!;
      try {
        final raw = await storage.read(qKey.storageKey);
        if (raw != null) {
          final envelope = StorageEnvelope.tryDecode(raw);
          if (envelope == null) {
            discardStored(storage, qKey);
            stream.emitLoading(key);
          } else if (envelope.isExpired) {
            if (config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
              final restoredData = currentCodec.decode(envelope.payload);
              final restoredEntry = CacheEntry<T>(
                restoredData,
                createdAt: envelope.createdAt,
                expiresAt: envelope.expiresAt,
                timeToLive: envelope.timeToLive,
                source: DataSource.storage,
              );
              cache.putEntry(qKey, restoredEntry);
              stream.emitRefreshing(
                key,
                restoredData,
                metadata: restoredEntry.metadata,
              );
            } else {
              deleteStored(storage, qKey);
              stream.emitLoading(key);
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
            stream.emitData(
              key,
              restoredData,
              metadata: restoredEntry.metadata,
            );
          }
        } else {
          stream.emitLoading(key);
        }
      } catch (error, stackTrace) {
        discardStored(storage, qKey, error, stackTrace);
        stream.emitLoading(key);
      }
    } else {
      stream.emitLoading(key);
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

        // Persist to L2 storage asynchronously if configured
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
            writeStored(storage, qKey, envelope.encode());
          } catch (error, stackTrace) {
            reportPersistenceError(qKey, error, stackTrace);
          }
        }

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

  @override
  bool canReleaseKey(K key) => super.canReleaseKey(key) && !isConnectedKey(key);

  @override
  void releaseKeyState(K key) {
    _lastLoadedData.remove(key);
    _pausedKeys.remove(key);
    super.releaseKeyState(key);
  }

  void _cleanupKey(K key) {
    _connectingKeys.remove(key);
    _cancelTokens.remove(key)?.cancel(reason: 'Stream reconnected');
    _subscriptions.remove(key)?.cancel().ignore();
  }

  /// Disconnects the upstream stream subscription for [key].
  Future<void> disconnectKey(K key) async {
    onDisconnect?.call(key);
    _connectingKeys.remove(key);
    _cancelTokens.remove(key)?.cancel(reason: 'Stream disconnected');
    final sub = _subscriptions.remove(key);
    await sub?.cancel();
  }

  /// Connects to the upstream stream for multiple [keys] using [parameter].
  Future<void> connectKeys(Iterable<K> keys, P parameter) =>
      Future.wait(keys.map((k) => connectKey(k, parameter)));

  /// Disconnects the upstream stream subscriptions for multiple [keys].
  Future<void> disconnectKeys(Iterable<K> keys) =>
      Future.wait(keys.map(disconnectKey));

  /// Watches state updates for a single [key], managing automatic connection.
  StatefulStream<T> watchKey(K key, {P? initialParameter, bool eager = false}) {
    if (eager && initialParameter != null && !isConnectedKey(key)) {
      connectKey(key, initialParameter).ignore();
    }

    final keyStream = stream.streamOf(key);

    return StatefulStream<T>(
      Stream.multi((controller) {
        _activeWatchers[key] = (_activeWatchers[key] ?? 0) + 1;
        if (initialParameter != null && !isConnectedKey(key)) {
          connectKey(key, initialParameter).ignore();
        }
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

      final storage = storageFor(qKey);
      final currentCodec = codec;
      if (storage != null && currentCodec != null) {
        final raw = await storage.read(qKey.storageKey);
        if (raw != null) {
          try {
            final envelope = StorageEnvelope.tryDecode(raw);
            if (envelope == null) {
              discardStored(storage, qKey);
            } else if (envelope.isExpired) {
              if (config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
                final restoredData = currentCodec.decode(envelope.payload);
                final restoredEntry = CacheEntry<T>(
                  restoredData,
                  createdAt: envelope.createdAt,
                  expiresAt: envelope.expiresAt,
                  timeToLive: envelope.timeToLive,
                  source: DataSource.storage,
                );
                cache.putEntry(qKey, restoredEntry);
                stream.emitRefreshing(
                  key,
                  restoredData,
                  metadata: restoredEntry.metadata,
                );
              } else {
                deleteStored(storage, qKey);
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
              stream.emitData(
                key,
                restoredData,
                metadata: restoredEntry.metadata,
              );
              return restoredData;
            }
          } catch (error, stackTrace) {
            discardStored(storage, qKey, error, stackTrace);
          }
        }
      }
    }

    final keyStream = stream.streamOf(key);
    final streamToAwait = forceRefresh ? keyStream.skipCurrent() : keyStream;

    final stateFuture = streamToAwait.firstWhere(
      (s) =>
          (s is DataLoaded<T> && s is! DataRefreshing<T>) || s is DataError<T>,
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

  @override
  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => getKey(k, parameter, forceRefresh: forceRefresh)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  Future<Map<K, T>> refreshKeys(Iterable<K> keys, P parameter) =>
      getAll(keys, parameter, forceRefresh: true);

  @override
  void triggerKeys(Iterable<K> keys, P parameter, {bool forceRefresh = false}) {
    for (final k in keys) {
      triggerKey(k, parameter, forceRefresh: forceRefresh);
    }
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
        writeStored(storage, qKey, envelope.encode());
      } catch (error, stackTrace) {
        reportPersistenceError(qKey, error, stackTrace);
      }
    }

    runSideEffect(() => sideEffects?.onData?.call(key, data, parameter));
    return data;
  }

  @override
  void invalidateKey(K key) {
    disconnectKey(key).ignore();
    super.invalidateKey(key);
  }

  @override
  void invalidate() {
    for (final key in stream.activeKeys) {
      disconnectKey(key).ignore();
    }
    super.invalidate();
  }

  @override
  Future<void> removeKey(K key) async {
    await disconnectKey(key);
    _lastLoadedData.remove(key);
    _activeWatchers.remove(key);
    _pausedKeys.remove(key);
    _connectingKeys.remove(key);
    await super.removeKey(key);
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
    // Snapshot and clear first: callbacks may touch the maps while we await.
    final tokens = List.of(_cancelTokens.values);
    final subs = List.of(_subscriptions.values);
    _cancelTokens.clear();
    _subscriptions.clear();
    for (final token in tokens) {
      token.cancel(reason: 'KeyedStreamTrooper disposed');
    }
    for (final sub in subs) {
      await sub.cancel();
    }
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
  StatefulStream<T> get stream => _parent.stream.streamOf(_key);

  @override
  StatefulStream<T> watch({P? initialParameter, bool eager = false}) =>
      _parent.watchKey(_key, initialParameter: initialParameter, eager: eager);

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) =>
      _parent.getKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) =>
      _parent.triggerKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  Future<T> refresh(P parameter) => _parent.refreshKey(_key, parameter);

  @override
  StatefulData<T> current() => _parent.currentKey(_key);

  @override
  T? currentData() => _parent.currentKeyData(_key);

  @override
  void invalidate() => _parent.invalidateKey(_key);
}
