import 'dart:async';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/cache_entry.dart';
import 'package:trooper/src/storage/storage_envelope.dart';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/trooper.dart';
import 'package:trooper/src/effects/trooper_side_effects.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// Function signature for creating an upstream push stream.
///
/// Can return a [Stream] directly or a [Future] completing with a [Stream]
/// for asynchronous connection setup, authentication, or handshakes.
typedef StreamFactory<T, P extends Parameter> =
    FutureOr<Stream<T>> Function(P parameter, TrooperCancelToken cancelToken);

/// A Trooper managing a reactive, push-based data stream.
///
/// Designed for live sources such as WebSockets, Server-Sent Events (SSE),
/// Bluetooth LE notifications, device sensors, or Firebase Realtime feeds.
///
/// Features:
/// - **Automatic Lifecycle**: Connects to upstream stream on-demand when watched,
///   and disconnects when the last listener unsubscribes (unless [keepAlive] is true).
/// - **Stateful Replay**: New subscribers immediately receive the latest emitted state.
/// - **L1 Cache Integration**: Incoming data updates [cache], accessible synchronously via [currentData].
/// - **Async Read**: [read] returns the latest data immediately or awaits the next stream event.
/// - **Bi-Directional Support**: Optional [onConnect] and [onRefresh] hooks to send commands over the stream.
/// - **Comprehensive SideEffects**: Lifecycle callbacks on connection, data, error, and completion.
///
/// ### Example:
/// ```dart
/// final cryptoTicker = StreamTrooper<double, (String symbol,)>(
///   name: 'crypto_ticker',
///   streamFactory: (param, cancelToken) => webSocket.subscribeToTicker(param.$1),
///   onRefresh: (param) => webSocket.send({'cmd': 'poll', 'symbol': param.$1}),
/// );
///
/// // Watch live price updates:
/// cryptoTicker.watch(('BTC',)).dataStream.listen((price) {
///   print('Live BTC price: $price');
/// });
/// ```
class StreamTrooper<T, P extends Parameter> extends Trooper<T, P> {
  /// Creates a [StreamTrooper] with the provided [streamFactory].
  StreamTrooper({
    required super.namespace,
    required this.streamFactory,
    this.codec,
    this.onConnect,
    this.onRefresh,
    this.onDisconnect,
    super.config,
    super.sideEffects,
    super.cache,
    super.queryQueue,
    super.telemetry,
    this.keepAlive = false,
    bool autoConnect = false,
    StatefulData<T> initialState = const DataInitial(),
  }) : super(
         streamController: StatefulStreamController<T>(
           initialState: initialState,
         ),
       ) {
    // If autoConnect is requested and P is the empty record (), connect immediately
    if (autoConnect && const () is P) {
      connect(const () as P).ignore();
    }
  }

  /// Factory method for parameterless streams.
  static StreamTrooper<T, ()> fromStream<T>({
    required String namespace,
    required FutureOr<Stream<T>> Function() stream,
    TrooperCodec<T>? codec,
    FutureOr<void> Function(TrooperCancelToken cancelToken)? onConnect,
    FutureOr<void> Function()? onRefresh,
    FutureOr<void> Function()? onDisconnect,
    TrooperConfig? config,
    TrooperSideEffects<T, ()>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    bool keepAlive = false,
    bool autoConnect = false,
    StatefulData<T> initialState = const DataInitial(),
  }) => StreamTrooper<T, ()>(
    namespace: namespace,
    streamFactory: (_, _) => stream(),
    codec: codec,
    onConnect: onConnect != null ? (_, token) => onConnect(token) : null,
    onRefresh: onRefresh != null ? (_) => onRefresh() : null,
    onDisconnect: onDisconnect,
    config: config,
    sideEffects: sideEffects,
    cache: cache,
    queryQueue: queryQueue,
    telemetry: telemetry,
    keepAlive: keepAlive,
    autoConnect: autoConnect,
    initialState: initialState,
  );

  /// Factory creating the upstream [Stream].
  final StreamFactory<T, P> streamFactory;

  /// Optional codec for L2 storage serialization and hydration.
  final TrooperCodec<T>? codec;

  /// Optional hook invoked when connecting to the upstream stream.
  ///
  /// Useful for sending initial subscription frames, authentication, or starting monitoring.
  final FutureOr<void> Function(P parameter, TrooperCancelToken cancelToken)?
  onConnect;

  /// Optional hook invoked when refreshing data via [refresh] or [read].
  ///
  /// Useful for requesting immediate snapshots or polling fresh data over an active socket.
  final FutureOr<void> Function(P parameter)? onRefresh;

  /// Optional hook invoked when the upstream stream is disconnected via [disconnect].
  ///
  /// Useful for sending unsubscribe frames or cleaning up resources on the server side.
  final FutureOr<void> Function()? onDisconnect;

  /// If `true`, the upstream subscription stays active even when no active listeners remain.
  /// If `false` (default), the upstream stream cancels when the last listener unsubscribes.
  final bool keepAlive;

  StreamSubscription<T>? _subscription;
  TrooperCancelToken? _cancelToken;
  P? _currentParam;
  T? _lastLoadedData;
  int _activeWatchers = 0;
  bool _isPaused = false;
  bool _isConnecting = false;

  /// Whether upstream streaming is temporarily paused via [pause].
  bool get isPaused => _isPaused;

  /// Whether an upstream subscription is currently active or connecting.
  bool get isConnected => _subscription != null || _isConnecting;

  /// Manually connects to the upstream stream using [parameter].
  Future<void> connect(P parameter) async {
    recordParam(parameter);

    // If already connected or connecting with the same parameter, keep existing connection
    if ((_subscription != null || _isConnecting) &&
        _currentParam == parameter) {
      return;
    }

    _isConnecting = true;
    _cancelToken?.cancel('Stream reconnected');
    _cancelToken = null;
    final oldSub = _subscription;
    _subscription = null;
    oldSub?.cancel().ignore();
    _currentParam = parameter;

    final token = TrooperCancelToken();
    _cancelToken = token;
    final qKey = buildQueryKey(parameter);

    // Emit loading if no current data or if stale policy discards stale data,
    // otherwise emit refreshing (SWR).
    final current = streamController.currentData;
    if (current != null &&
        config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
      streamController.emitRefreshing(current);
    } else if (current == null &&
        config.hasCache &&
        config.storage != null &&
        codec != null) {
      final storage = config.storage!;
      final currentCodec = codec!;
      try {
        final raw = await storage.read(qKey.storageKey);
        if (raw != null) {
          final envelope = StorageEnvelope.tryDecode(raw);
          if (envelope == null) {
            storage.delete(qKey.storageKey).ignore();
            streamController.emitLoading();
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
              streamController.emitRefreshing(
                restoredData,
                metadata: restoredEntry.metadata,
              );
            } else {
              storage.delete(qKey.storageKey).ignore();
              streamController.emitLoading();
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
            streamController.emitData(
              restoredData,
              metadata: restoredEntry.metadata,
            );
          }
        } else {
          streamController.emitLoading();
        }
      } catch (_) {
        storage.delete(qKey.storageKey).ignore();
        streamController.emitLoading();
      }
    } else {
      streamController.emitLoading();
    }

    if (telemetry.hasListeners) {
      telemetry.emit(RequestStartedEvent(qKey));
    }
    runSideEffect(() => sideEffects?.onRequestStarted?.call(parameter));

    try {
      _isConnecting = true;
      if (onConnect != null) {
        final connectResult = onConnect!(parameter, token);
        if (connectResult is Future) {
          await connectResult;
        }
        if (token.isCancelled) return;
      }

      await _resolveAndSubscribeUpstream(parameter, token, qKey);
    } catch (error, stackTrace) {
      if (!token.isCancelled) {
        _handleUpstreamError(error, stackTrace, qKey, parameter);
      }
    } finally {
      if (_cancelToken == token) {
        _isConnecting = false;
      }
    }
  }

  Future<void> _resolveAndSubscribeUpstream(
    P param,
    TrooperCancelToken token,
    QueryKey qKey,
  ) async {
    final upstreamOrFuture = streamFactory(param, token);
    final Stream<T> upstream;
    if (upstreamOrFuture is Future<Stream<T>>) {
      upstream = await upstreamOrFuture;
    } else {
      upstream = upstreamOrFuture;
    }
    if (token.isCancelled) return;
    _subscribeUpstream(upstream, qKey, param);
  }

  void _subscribeUpstream(Stream<T> upstream, QueryKey qKey, P param) {
    _subscription = upstream.listen(
      (data) {
        if (sideEffects != null &&
            sideEffects?.transformRequestResult != null) {
          runSideEffect(() async {
            T transformation = await sideEffects!.transformRequestResult!.call(
              data,
              param,
            );
            data = transformation;
          });
        }
        _lastLoadedData = data;
        if (config.hasCache) {
          cache.put(
            qKey,
            data,
            timeToLive: config.timeToLive,
            source: DataSource.network,
          );
        }
        final entry = config.hasCache ? cache.getEntry<T>(qKey) : null;
        streamController.emitData(data, metadata: entry?.metadata);

        // Persist to L2 storage asynchronously if configured
        final storage = config.storage;
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
            storage.write(qKey.storageKey, envelope.encode()).ignore();
          } catch (error, stacktrace) {
            if (telemetry.hasListeners) {
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
        runSideEffect(() => sideEffects?.onData?.call(data, param));
      },
      onError: (Object error, StackTrace stackTrace) {
        _handleUpstreamError(error, stackTrace, qKey, param);
      },
      onDone: () {
        _subscription = null;
        _cancelToken = null;
      },
      cancelOnError: false,
    );
  }

  void _handleUpstreamError(
    Object error,
    StackTrace stackTrace,
    QueryKey qKey,
    P param,
  ) {
    streamController.emitError(
      error,
      stackTrace: stackTrace,
      staleData: _lastLoadedData ?? streamController.currentData,
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
    runSideEffect(() => sideEffects?.onError?.call(error, stackTrace, param));
  }

  /// Disconnects the upstream stream subscription and cancels the associated [TrooperCancelToken].
  Future<void> disconnect() async {
    onDisconnect?.call();
    _cancelToken?.cancel('Stream disconnected');
    _cancelToken = null;
    _isConnecting = false;
    final sub = _subscription;
    _subscription = null;
    _currentParam = null;
    await sub?.cancel();
  }

  @override
  StatefulStream<T> watch(P parameter, {bool eager = true}) {
    if (eager && !isConnected) {
      connect(parameter).ignore();
    }

    // Wrap the returned stream to track active watcher lifecycle
    return StatefulStream<T>(
      Stream<StatefulData<T>>.multi((listener) {
        _activeWatchers++;
        if (!isConnected) {
          connect(parameter).ignore();
        }
        final sub = streamController.stream.listen(
          listener.addSync,
          onError: listener.addError,
          onDone: listener.close,
        );

        listener.onCancel = () async {
          await sub.cancel();
          _activeWatchers--;
          if (_activeWatchers <= 0 && !keepAlive) {
            _activeWatchers = 0;
            await disconnect();
          }
        };
      }, isBroadcast: true),
      currentStateProvider: () => streamController.currentState,
      rawBroadcastStream: streamController.stream.rawBroadcastStream,
    );
  }

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) async {
    recordParam(parameter);
    final qKey = buildQueryKey(parameter);

    if (!forceRefresh && config.hasCache) {
      final cached = cache.get<T>(qKey);
      if (cached != null && !cache.isStale(qKey)) {
        return cached;
      }

      final storage = config.storage;
      final currentCodec = codec;
      if (storage != null && currentCodec != null) {
        final raw = await storage.read(qKey.storageKey);
        if (raw != null) {
          try {
            final envelope = StorageEnvelope.tryDecode(raw);
            if (envelope == null) {
              storage.delete(qKey.storageKey).ignore();
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
                streamController.emitRefreshing(
                  restoredData,
                  metadata: restoredEntry.metadata,
                );
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
              streamController.emitData(
                restoredData,
                metadata: restoredEntry.metadata,
              );
              return restoredData;
            }
          } catch (_) {
            storage.delete(qKey.storageKey).ignore();
          }
        }
      }
    }

    final streamToAwait = forceRefresh
        ? streamController.stream.skipCurrent()
        : streamController.stream;

    final stateFuture = streamToAwait.firstWhere(
      (s) =>
          (s is DataLoaded<T> && s is! DataRefreshing<T>) || s is DataError<T>,
      orElse: () => throw const TrooperCancelledException(
        message: 'Stream closed before data was received',
      ),
    );

    final shouldDisconnectAfterRead = _activeWatchers == 0 && !keepAlive;

    try {
      if (forceRefresh && onRefresh != null) {
        if (!isConnected) {
          await connect(parameter);
        }
        await onRefresh!(parameter);
      } else if (forceRefresh || !isConnected) {
        await connect(parameter);
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
        await disconnect();
      }
    }
  }

  @override
  Future<T> refresh(P parameter) => get(parameter, forceRefresh: true);

  @override
  T set(T data, P parameter) {
    super.set(data, parameter);
    final storage = config.storage;
    final currentCodec = codec;
    if (storage != null && currentCodec != null) {
      try {
        final qKey = buildQueryKey(parameter);
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
        storage.write(qKey.storageKey, envelope.encode()).ignore();
      } catch (_) {
        // Non-critical persistence failure
      }
    }
    return data;
  }

  /// Invalidates cache, disconnects upstream, clears persistent storage, and resets state to [DataInitial].
  @override
  void invalidate() {
    _lastLoadedData = null;
    disconnect().ignore();
    super.invalidate();
  }

  /// Temporarily disconnects the upstream stream (e.g. app sent to background).
  @override
  Future<void> pause() async {
    cache.pause();
    if (isConnected) {
      _isPaused = true;
      await disconnect();
    }
  }

  /// Resumes the upstream connection if previously paused and watchers exist.
  @override
  FutureOr<void> resume() {
    cache.resume();
    if (_isPaused) {
      _isPaused = false;
      if (_activeWatchers > 0 || keepAlive) {
        final param = lastParam;
        if (param != null) {
          connect(param).ignore();
        }
      }
    }
  }

  /// Reconnects the upstream stream if disconnected or in an error state.
  @override
  FutureOr<void> recover() {
    if ((!isConnected && (_activeWatchers > 0 || keepAlive)) ||
        streamController.isError) {
      final param = lastParam;
      if (param != null) {
        connect(param).ignore();
      }
    }
  }

  /// Purges cache and re-establishes upstream connection with updated dependencies.
  @override
  FutureOr<void> didChangeDependencies() {
    final shouldReconnect = isConnected || _activeWatchers > 0 || keepAlive;
    invalidate();
    if (config.refreshAfterChangeDependencies && shouldReconnect) {
      final param = lastParam;
      if (param != null) {
        connect(param).ignore();
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await disconnect();
    await super.dispose();
  }
}

/// Convenience extension for parameterless [StreamTrooper] instances where `P` is `()`.
extension ParameterlessStreamTrooper<T> on StreamTrooper<T, ()> {
  /// Manually connects to the upstream stream without requiring an explicit `()` parameter.
  Future<void> connect() => this.connect(const ());
}
