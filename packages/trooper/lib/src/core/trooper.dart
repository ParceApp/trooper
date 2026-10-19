import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/effects/trooper_side_effects.dart';
import 'package:trooper/src/storage/storage_access.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// Abstract base class for all single-resource troopers.
///
/// Implements [Accessor] and [LifecycleAware], managing:
/// - Reactive state broadcast through [stream].
/// - In-memory L1 cache through [cache].
/// - Concurrency, deduplication, and cancellation through [queryQueue].
/// - Diagnostic telemetry through [telemetry].
/// - Configuration parameters through [config].
abstract base class Trooper<T, P extends Parameter>
    with LifecycleAware, StorageAccess
    implements Accessor<T, P> {
  /// Creates a [Trooper] with the specified [namespace] and dependencies.
  ///
  /// [config] can be set if a custom [TrooperConfig] is desired; otherwise, the static [defaultConfig] is used.
  /// In most of the use cases [cache], [queryQueue], and [telemetry] are provided by the framework, but they can be overridden for testing or advanced use cases.
  @internal
  Trooper({
    required this.namespace,
    this.sideEffects,
    TrooperConfig? config,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    StatefulData<T> initialState = const DataInitial(),
  }) : config = config ?? defaultConfig,
       _ownsCache = (cache == null),
       _ownsQueryQueue = (queryQueue == null),
       cache = cache ?? CacheStore(),
       queryQueue = queryQueue ?? TrooperQueryQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       streamController = StatefulStreamController<T>(
         initialState: initialState,
       );

  // Static configuration for defaults
  static TrooperConfig get defaultConfig => TrooperConfig.defaultConfig;

  /// Sets the default configuration for all troopers.
  /// This config can be overridden by individual troopers via their constructor.
  static void setDefaultConfig(TrooperConfig config) {
    TrooperConfig.setDefaultConfig(config);
  }

  final bool _ownsCache;
  final bool _ownsQueryQueue;

  /// Logical name of this query or resource family.
  @override
  final String namespace;

  /// Configuration defining TTL, stale policy, and persistence.
  @override
  final TrooperConfig config;

  /// Optional side-effect callbacks for lifecycle hooks.
  final TrooperSideEffects<T, P>? sideEffects;

  /// In-memory L1 cache store.
  final CacheStore cache;

  /// Concurrency and request queue.
  final TrooperQueryQueue queryQueue;

  /// Telemetry hub for diagnostic events.
  @override
  final TelemetryHub telemetry;

  /// Replay-enabled stateful stream controller.
  @internal
  final StatefulStreamController<T> streamController;

  /// The underlying [StatefulStream] emitting [StatefulData] transitions.
  @override
  StatefulStream<T> get stream => streamController.stream;

  P? _lastParam;
  bool _isDisposed = false;

  /// Whether this trooper has been disposed.
  bool get isDisposed => _isDisposed;

  /// The parameter used for the most recent operation, or `null` if none has been provided yet.
  P? get lastParam => _lastParam;

  /// Records the last executed parameter.
  @internal
  void recordParam(P parameter) {
    _lastParam = parameter;
  }

  /// Builds the unique [QueryKey] for this trooper.
  @internal
  QueryKey buildQueryKey(P parameter) => QueryKey(namespace, parameter);

  /// Returns `true` if [parameter] differs from the last used parameter.
  @internal
  bool isParamChanged(P parameter) {
    if (_lastParam == null) return false;
    return parameter != _lastParam;
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

  @override
  StatefulStream<T> watch({P? initialParameter, bool eager = false}) {
    if (eager && initialParameter != null) {
      final state = current();
      if (state is DataInitial ||
          isParamChanged(initialParameter) ||
          (config.hasCache && cache.isStale(buildQueryKey(initialParameter)))) {
        get(initialParameter).ignore();
      }
    }
    return streamController.stream;
  }

  @override
  StatefulData<T> current() => streamController.currentState;

  @override
  T? currentData() => streamController.currentData;

  /// Manually sets data in cache and emits [DataLoaded], returning the set [data].
  ///
  /// Useful internally for optimistic updates, cache seeding, or tests.
  T set(T data, P parameter) {
    recordParam(parameter);
    final key = buildQueryKey(parameter);

    if (config.hasCache) {
      cache.put(
        key,
        data,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
    }
    final entry = config.hasCache ? cache.getEntry<T>(key) : null;
    streamController.emitData(data, metadata: entry?.metadata);

    if (telemetry.hasListeners) {
      telemetry.emit(DataSetEvent(key, source: DataSource.local));
    }
    runSideEffect(() => sideEffects?.onData?.call(data, parameter));

    return data;
  }

  @override
  void invalidate() {
    queryQueue.cancelNamespace(namespace);
    cache.removeName(namespace);
    purgeStorage();
    _lastParam = null;
    streamController.emitInitial();
    if (telemetry.hasListeners) {
      telemetry.emit(CacheInvalidatedEvent(QueryKey(namespace, const ())));
    }
  }

  @override
  Future<T> refresh(P parameter) => get(parameter, forceRefresh: true);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) {
    get(parameter, forceRefresh: forceRefresh).ignore();
  }

  @override
  void pause() {
    cache.pause();
  }

  @override
  FutureOr<void> resume() {
    cache.resume();
  }

  /// Recovers the trooper state by re-fetching if currently in an error state.
  @override
  FutureOr<void> recover() {
    final param = _lastParam;
    if (streamController.isError && param != null) {
      refresh(param).ignore();
    }
  }

  /// Reacts to dependency/environment changes by purging cached data,
  /// cancelling in-flight requests, and re-fetching if active listeners exist.
  @override
  FutureOr<void> didChangeDependencies() {
    final param = _lastParam;
    queryQueue.cancelNamespace(namespace);
    invalidate();
    if (config.refreshAfterChangeDependencies &&
        streamController.hasListeners &&
        param != null) {
      refresh(param).ignore();
    }
  }

  /// Returns a read-only [Accessor] facade over this trooper.
  ///
  /// Prevents consumers from calling mutating methods or accessing internal state directly.
  late final Accessor<T, P> accessor = _BoundTrooperAccessor<T, P>(this);

  /// Callable shorthand returning the read-only [accessor].
  Accessor<T, P> call() => accessor;

  /// Closes stream controllers, timers, and any resources owned by this trooper.
  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await streamController.dispose();
    if (_ownsQueryQueue) {
      await queryQueue.dispose();
    }
    if (_ownsCache) {
      await cache.dispose();
    }
  }
}

/// Concrete, read-only [Accessor] facade delegating to an underlying [Trooper].
class _BoundTrooperAccessor<T, P extends Parameter> implements Accessor<T, P> {
  const _BoundTrooperAccessor(this._trooper);
  final Trooper<T, P> _trooper;

  @override
  StatefulStream<T> get stream => _trooper.stream;

  @override
  StatefulStream<T> watch({P? initialParameter, bool eager = false}) =>
      _trooper.watch(initialParameter: initialParameter, eager: eager);

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) =>
      _trooper.get(parameter, forceRefresh: forceRefresh);

  @override
  Future<T> refresh(P parameter) => _trooper.refresh(parameter);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) =>
      _trooper.trigger(parameter, forceRefresh: forceRefresh);

  @override
  StatefulData<T> current() => _trooper.current();

  @override
  T? currentData() => _trooper.currentData();

  @override
  void invalidate() => _trooper.invalidate();
}

/// Convenience extension for parameterless [Trooper] instances where `P` is `()`.
extension ParameterlessTrooper<T> on Trooper<T, ()> {
  /// Manually sets data in cache and emits [DataLoaded] without requiring an explicit `()` parameter.
  T set(T data) => this.set(data, const ());
}
