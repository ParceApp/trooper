import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/storage/storage_backend.dart';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/mutation_queue.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/keyed_local_trooper.dart';
import 'package:trooper/src/core/keyed_stream_trooper.dart';
import 'package:trooper/src/core/keyed_query_trooper.dart';
import 'package:trooper/src/core/local_trooper.dart';
import 'package:trooper/src/core/stream_trooper.dart';
import 'package:trooper/src/core/trooper_mutation.dart';
import 'package:trooper/src/core/query_trooper.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/pagination/load_more.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/effects/trooper_side_effects.dart';
import 'package:trooper/src/effects/trooper_keyed_side_effects.dart';
import 'package:trooper/src/effects/trooper_mutation_side_effects.dart';

/// Base class for business logic components, view models, and feature controllers.
///
/// [TrooperController] orchestrates a collection of managed [LifecycleAware] and [Invalidatable]
/// troopers, queries, streams, and mutations.
///
/// ### Core Responsibilities:
/// - **Declarative Field Declaration**: Fields can be declared directly at the attribute level
///   using `late final courses = query(...)` without requiring constructor assignment boilerplate.
/// - **Factory Builders**: Conveniently build [query], [keyedQuery], [stream],
///   [keyedStream], [local], [keyedLocal], and [mutation] instances with shared defaults.
/// - **Lifecycle Propagation & Hooks**: Propagates [initialize], [pause], [resume], [recover],
///   [didChangeDependencies], and [dispose] to all registered child troopers and [extraLifecycleChildren].
///   Provides overridable hooks like [onInit] and [onDispose].
/// - **Hierarchical Invalidation**: Implements [Invalidatable]. Calling [invalidate] or [clearAll]
///   invalidates all managed troopers and [extraInvalidatables] at once (ideal target for
///   `invalidateOnSuccess: \[this\]`).
///
/// ### Example:
/// ```dart
/// class CourseController extends TrooperController {
///   CourseController({super.defaultStorage});
///
///   // Directly declared as attributes with `late final` (lazy, zero-boilerplate):
///   late final courses = query<List<String>, ()>(
///     namespace: 'courses',
///     fetch: (param) => api.getCourses(),
///   );
///
///   late final addCourse = mutation<String, ({String title})>(
///     namespace: 'addCourse',
///     action: (param) => api.createCourse(param.title),
///     invalidateOnSuccess: [this], // invalidates all troopers in this controller
///   );
/// }
/// ```
///
/// ### Extending
/// Extend this class; do not `implements` it. Implementing it is not
/// supported, and new members can be added in minor releases.
abstract class TrooperController with LifecycleAware implements Invalidatable {
  /// Creates a [TrooperController] with optional shared default configuration.
  TrooperController({
    this.defaultConfig,
    this.defaultStorage,
    this.defaultCache,
    this.defaultTelemetry,
    this.defaultQueryQueue,
    this.defaultMutationQueue,
  });

  /// Default configuration used by child troopers unless explicitly overridden.
  final TrooperConfig? defaultConfig;

  /// Default persistent storage backend passed to child troopers.
  final StorageBackend? defaultStorage;

  /// Default cache store shared by child troopers.
  final CacheStore? defaultCache;

  /// Default telemetry hub shared by child troopers.
  final TelemetryHub? defaultTelemetry;

  /// Default request orchestrator shared by child troopers.
  final TrooperQueryQueue? defaultQueryQueue;

  /// Default mutation queue shared by child mutations.
  final TrooperMutationQueue? defaultMutationQueue;

  final List<LifecycleAware> _managedChildren = [];
  final List<Invalidatable> _managedInvalidatables = [];
  bool _isDisposed = false;

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Total number of currently managed child components.
  int get managedCount => _managedChildren.length;

  /// Unmodifiable view of all managed [LifecycleAware] child components.
  List<LifecycleAware> get managedChildren =>
      List.unmodifiable(_managedChildren);

  /// Unmodifiable view of all managed [Invalidatable] child components.
  List<Invalidatable> get managedInvalidatables =>
      List.unmodifiable(_managedInvalidatables);

  /// Additional [Invalidatable] targets to invalidate when [invalidate] or [clearAll] is called.
  ///
  /// Override this getter to declaratively link external services, repositories,
  /// or sibling controllers to this controller's invalidation cascade.
  ///
  /// ```dart
  /// class DashboardController extends TrooperController {
  ///   DashboardController(this.authController);
  ///   final Invalidatable authController;
  ///
  ///   @override
  ///   List<Invalidatable> get extraInvalidatables => [authController];
  /// }
  /// ```
  List<Invalidatable> get extraInvalidatables => const [];

  /// Additional [LifecycleAware] components to include in lifecycle orchestration.
  ///
  /// Override this getter to declaratively link external background services,
  /// sockets, or pollers to this controller's lifecycle events ([initialize], [pause],
  /// [resume], [recover], [didChangeDependencies], [dispose]).
  ///
  /// ```dart
  /// class FeedController extends TrooperController {
  ///   FeedController(this.service);
  ///   final LifecycleAware service;
  ///
  ///   @override
  ///   List<LifecycleAware> get extraLifecycleChildren => [service];
  /// }
  /// ```
  List<LifecycleAware> get extraLifecycleChildren => const [];

  /// Hook called at the start of [initialize].
  ///
  /// Override to perform asynchronous bootstrapping (e.g. prefetching data,
  /// warming up caches, or establishing connections).
  ///
  /// ```dart
  /// @override
  /// Future<void> onInit() async {
  ///   // Bootstrap controller resources
  /// }
  /// ```
  @protected
  FutureOr<void> onInit() {}

  /// Hook called at the start of [pause].
  @protected
  FutureOr<void> onPause() {}

  /// Hook called at the start of [resume].
  @protected
  FutureOr<void> onResume() {}

  /// Hook called at the start of [recover].
  @protected
  FutureOr<void> onRecover() {}

  /// Hook called at the start of [didChangeDependencies].
  @protected
  FutureOr<void> onDependenciesChanged() {}

  /// Hook called at the start of [dispose], before managed children are disposed.
  ///
  /// ```dart
  /// @override
  /// Future<void> onDispose() async {
  ///   // Clean up controller resources
  /// }
  /// ```
  @protected
  FutureOr<void> onDispose() {}

  /// Manages an existing [child], tracking its lifecycle and invalidation.
  /// If [child] is a [LifecycleAware] or [Invalidatable], it will be automatically disposed and invalidated
  /// when this controller is disposed or invalidated.
  /// If [child] is **not** a [LifecycleAware] or [Invalidatable], it will be ignored for lifecycle and invalidation purposes.
  ///
  /// Returns the passed [child] for chained assignment.
  T manage<T extends Object>(T child) {
    if (_isDisposed) {
      throw StateError(
        'Cannot register child to an already disposed TrooperController.',
      );
    }
    if (child is LifecycleAware && !_managedChildren.contains(child)) {
      _managedChildren.add(child);
    }
    if (child is Invalidatable && !_managedInvalidatables.contains(child)) {
      _managedInvalidatables.add(child);
    }
    return child;
  }

  /// Manages a batch of [children], tracking their lifecycle and invalidation.
  /// If a [child] is a [LifecycleAware] or [Invalidatable], it will be automatically disposed and invalidated
  /// when this controller is disposed or invalidated.
  /// If a [child] is **not** a [LifecycleAware] or [Invalidatable], it will be ignored for lifecycle and invalidation purposes.
  void manageAll(Iterable<Object> children) => children.forEach(manage);

  /// Unregisters a previously managed [child] without disposing it.
  bool unregister(Object child) {
    var removed = false;
    if (child is LifecycleAware) {
      removed = _managedChildren.remove(child) || removed;
    }
    if (child is Invalidatable) {
      removed = _managedInvalidatables.remove(child) || removed;
    }
    return removed;
  }

  TrooperConfig _resolveConfig(TrooperConfig? config) {
    var resolved = config ?? defaultConfig ?? const TrooperConfig();
    if (resolved.storage == null && defaultStorage != null) {
      resolved = resolved.copyWith(storage: defaultStorage);
    }
    return resolved;
  }

  /// Creates and registers a new [QueryTrooper] managed by this controller.
  ///
  /// Shares [defaultCache], [defaultQueryQueue], and [defaultTelemetry] with the controller
  /// unless explicitly overridden. Disposing the query individually will not dispose
  /// shared controller services.
  ///
  /// ```dart
  /// class UserController extends TrooperController {
  ///   late final user = query<String, ({String id})>(
  ///     namespace: 'user',
  ///     fetch: (param) async => 'User ${param.id}',
  ///   );
  /// }
  /// ```
  QueryTrooper<T, P> query<T, P extends Record>({
    required String namespace,
    Future<T> Function(P param)? fetch,
    Future<T> Function(P param, TrooperCancelToken token)? cancellableFetch,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    TrooperSideEffects<T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
  }) {
    assert(
      fetch != null || cancellableFetch != null,
      'Either fetch or cancellableFetch must be provided',
    );
    final resolvedConfig = _resolveConfig(config);
    final trooper = cancellableFetch != null
        ? QueryTrooper<T, P>.cancellable(
            namespace: namespace,
            fetch: cancellableFetch,
            codec: codec,
            config: resolvedConfig,
            sideEffects: sideEffects,
            cache: cache ?? defaultCache,
            queryQueue: queryQueue ?? defaultQueryQueue,
            telemetry: telemetry ?? defaultTelemetry,
          )
        : QueryTrooper<T, P>(
            namespace: namespace,
            fetch: fetch!,
            codec: codec,
            config: resolvedConfig,
            sideEffects: sideEffects,
            cache: cache ?? defaultCache,
            queryQueue: queryQueue ?? defaultQueryQueue,
            telemetry: telemetry ?? defaultTelemetry,
          );
    return manage(trooper);
  }

  /// Creates and registers a new [KeyedQueryTrooper] managed by this controller.
  ///
  /// Partitioned by entity key [K]. Shares [defaultCache], [defaultQueryQueue],
  /// and [defaultTelemetry] with the controller unless overridden.
  ///
  /// ```dart
  /// class PostController extends TrooperController {
  ///   late final post = keyedQuery<int, String, ()>(
  ///     namespace: 'post',
  ///     fetch: (id, _) async => 'Post #$id',
  ///   );
  /// }
  /// ```
  KeyedQueryTrooper<K, T, P> keyedQuery<K extends Object, T, P extends Record>({
    required String namespace,
    Future<T> Function(K key, P param)? fetch,
    Future<T> Function(K key, P param, TrooperCancelToken token)?
    cancellableFetch,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    bool releaseUnwatchedKeys = false,
  }) {
    assert(
      fetch != null || cancellableFetch != null,
      'Either fetch or cancellableFetch must be provided',
    );
    final resolvedConfig = _resolveConfig(config);
    final trooper = cancellableFetch != null
        ? KeyedQueryTrooper<K, T, P>.cancellable(
            namespace: namespace,
            fetch: cancellableFetch,
            codec: codec,
            config: resolvedConfig,
            sideEffects: sideEffects,
            cache: cache ?? defaultCache,
            queryQueue: queryQueue ?? defaultQueryQueue,
            telemetry: telemetry ?? defaultTelemetry,
            releaseUnwatchedKeys: releaseUnwatchedKeys,
          )
        : KeyedQueryTrooper<K, T, P>(
            namespace: namespace,
            fetch: fetch!,
            codec: codec,
            config: resolvedConfig,
            sideEffects: sideEffects,
            cache: cache ?? defaultCache,
            queryQueue: queryQueue ?? defaultQueryQueue,
            telemetry: telemetry ?? defaultTelemetry,
            releaseUnwatchedKeys: releaseUnwatchedKeys,
          );
    return manage(trooper);
  }

  /// Creates and registers a new [LoadMore] feed over an existing page query.
  ///
  /// The [source] query takes `({F filter, PP page})`, so all type arguments are
  /// inferred from it. The feed is disposed and invalidated with this controller.
  ///
  /// ```dart
  /// class ArticleController extends TrooperController {
  ///   late final _articlePage =
  ///       query<Page<Article>, ({({String category}) filter, int page})>(
  ///         namespace: 'articles',
  ///         fetch: (p) => api.getArticles(category: p.filter.category, page: p.page),
  ///         config: const TrooperConfig.noCache(),
  ///       );
  ///
  ///   late final articleFeed = loadMore(
  ///     source: _articlePage,
  ///     initialPageParam: 1,
  ///     nextPageParam: (last, all) => last.hasMore ? all.length + 1 : null,
  ///   );
  /// }
  /// ```
  LoadMore<TPage, F, PP> loadMore<TPage, F extends Record, PP extends Object>({
    required Accessor<TPage, ({F filter, PP page})> source,
    required PP initialPageParam,
    required PP? Function(TPage lastPage, List<TPage> allPages) nextPageParam,
  }) => manage(
    LoadMore<TPage, F, PP>(
      source: source,
      initialPageParam: initialPageParam,
      nextPageParam: nextPageParam,
    ),
  );

  /// Creates and registers a new [LocalTrooper] managed by this controller.
  ///
  /// Manages in-memory mutable local state with optional persistent backing.
  ///
  /// ```dart
  /// class SettingsController extends TrooperController {
  ///   late final theme = local<String, ()>(
  ///     namespace: 'theme',
  ///     initialValue: 'system',
  ///   );
  /// }
  /// ```
  LocalTrooper<T, P> local<T, P extends Record>({
    required String namespace,
    required T initialValue,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    TrooperSideEffects<T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
  }) {
    final trooper = LocalTrooper<T, P>(
      namespace: namespace,
      initialValue: initialValue,
      codec: codec,
      config: _resolveConfig(config),
      sideEffects: sideEffects,
      cache: cache ?? defaultCache,
      queryQueue: queryQueue ?? defaultQueryQueue,
      telemetry: telemetry ?? defaultTelemetry,
    );
    return manage(trooper);
  }

  /// Creates and registers a new [KeyedLocalTrooper] managed by this controller.
  ///
  /// Manages dynamic collections of in-memory mutable local state partitioned by key [K].
  ///
  /// ```dart
  /// class ChatController extends TrooperController {
  ///   late final drafts = keyedLocal<String, String, ()>(
  ///     namespace: 'drafts',
  ///     initialValue: '',
  ///   );
  /// }
  /// ```
  KeyedLocalTrooper<K, T, P> keyedLocal<K extends Object, T, P extends Record>({
    required String namespace,
    T? initialValue,
    T Function(K key)? initialValueFactory,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
  }) {
    assert(
      initialValue != null || initialValueFactory != null,
      'Either initialValue or initialValueFactory must be provided',
    );
    final resolvedConfig = _resolveConfig(config);
    final trooper = initialValueFactory != null
        ? KeyedLocalTrooper<K, T, P>.builder(
            namespace: namespace,
            initialValueFactory: initialValueFactory,
            codec: codec,
            config: resolvedConfig,
            sideEffects: sideEffects,
            cache: cache ?? defaultCache,
            queryQueue: queryQueue ?? defaultQueryQueue,
            telemetry: telemetry ?? defaultTelemetry,
          )
        : KeyedLocalTrooper<K, T, P>(
            namespace: namespace,
            initialValue: initialValue as T,
            codec: codec,
            config: resolvedConfig,
            sideEffects: sideEffects,
            cache: cache ?? defaultCache,
            queryQueue: queryQueue ?? defaultQueryQueue,
            telemetry: telemetry ?? defaultTelemetry,
          );
    return manage(trooper);
  }

  /// Creates and registers a new [StreamTrooper] managed by this controller.
  ///
  /// Connects to a continuous reactive data stream (e.g. WebSocket, broadcast channel).
  ///
  /// ```dart
  /// class PriceController extends TrooperController {
  ///   late final btcPrice = stream<double, ()>(
  ///     namespace: 'btc_price',
  ///     streamFactory: (_, _) => Stream.periodic(
  ///       const Duration(seconds: 1),
  ///       (i) => 50000.0 + i,
  ///     ),
  ///   );
  /// }
  /// ```
  StreamTrooper<T, P> stream<T, P extends Record>({
    required String namespace,
    required StreamFactory<T, P> streamFactory,
    FutureOr<void> Function(P parameter, TrooperCancelToken cancelToken)?
    onConnect,
    FutureOr<void> Function(P parameter)? onRefresh,
    FutureOr<void> Function()? onDisconnect,
    TrooperConfig? config,
    TrooperSideEffects<T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    bool keepAlive = false,
    bool autoConnect = false,
    StatefulData<T> initialState = const DataInitial(),
  }) {
    final trooper = StreamTrooper<T, P>(
      namespace: namespace,
      streamFactory: streamFactory,
      onConnect: onConnect,
      onRefresh: onRefresh,
      onDisconnect: onDisconnect,
      config: _resolveConfig(config),
      sideEffects: sideEffects,
      cache: cache ?? defaultCache,
      queryQueue: queryQueue ?? defaultQueryQueue,
      telemetry: telemetry ?? defaultTelemetry,
      keepAlive: keepAlive,
      autoConnect: autoConnect,
      initialState: initialState,
    );
    return manage(trooper);
  }

  /// Creates and registers a new [KeyedStreamTrooper] managed by this controller.
  ///
  /// Manages multi-channel stream upstreams partitioned by entity key [K].
  ///
  /// ```dart
  /// class RoomController extends TrooperController {
  ///   late final roomChat = keyedStream<String, String, ()>(
  ///     namespace: 'room_chat',
  ///     streamFactory: (roomId, _, _) => Stream.value('Joined $roomId'),
  ///   );
  /// }
  /// ```
  KeyedStreamTrooper<K, T, P>
  keyedStream<K extends Object, T, P extends Record>({
    required String namespace,
    required KeyedStreamFactory<K, T, P> streamFactory,
    FutureOr<void> Function(K key, P parameter, TrooperCancelToken cancelToken)?
    onConnect,
    FutureOr<void> Function(K key, P parameter)? onRefresh,
    FutureOr<void> Function(K key)? onDisconnect,
    TrooperConfig? config,
    KeyedTrooperSideEffects<K, T, P>? sideEffects,
    bool keepAlive = false,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    bool releaseUnwatchedKeys = false,
  }) {
    final trooper = KeyedStreamTrooper<K, T, P>(
      namespace: namespace,
      streamFactory: streamFactory,
      onConnect: onConnect,
      onRefresh: onRefresh,
      onDisconnect: onDisconnect,
      config: _resolveConfig(config),
      sideEffects: sideEffects,
      keepAlive: keepAlive,
      cache: cache ?? defaultCache,
      queryQueue: queryQueue ?? defaultQueryQueue,
      telemetry: telemetry ?? defaultTelemetry,
      releaseUnwatchedKeys: releaseUnwatchedKeys,
    );
    return manage(trooper);
  }

  /// Creates and registers a new [TrooperMutation] managed by this controller.
  ///
  /// Runs command-based mutations with sequential queueing and automatic invalidation.
  ///
  /// ```dart
  /// class ArticleController extends TrooperController {
  ///   late final createArticle = mutation<String, ({String title})>(
  ///     namespace: 'createArticle',
  ///     action: (param) async => 'Created ${param.title}',
  ///     invalidateOnSuccess: [this],
  ///   );
  /// }
  /// ```
  TrooperMutation<T, P> mutation<T, P extends Record>({
    required String namespace,
    Future<T> Function(P param)? action,
    Future<T> Function(P param, TrooperCancelToken token)? cancellableAction,
    List<Invalidatable>? invalidateOnSuccess,
    TrooperMutationSideEffects<T, P>? sideEffects,
    TrooperMutationQueue? queue,
    TelemetryHub? telemetry,
  }) {
    assert(
      action != null || cancellableAction != null,
      'Either action or cancellableAction must be provided',
    );
    final trooper = cancellableAction != null
        ? TrooperMutation<T, P>.cancellable(
            namespace: namespace,
            action: cancellableAction,
            invalidateOnSuccess: invalidateOnSuccess,
            sideEffects: sideEffects,
            queue: queue ?? defaultMutationQueue,
            telemetry: telemetry ?? defaultTelemetry,
          )
        : TrooperMutation<T, P>(
            namespace: namespace,
            action: action!,
            invalidateOnSuccess: invalidateOnSuccess,
            sideEffects: sideEffects,
            queue: queue ?? defaultMutationQueue,
            telemetry: telemetry ?? defaultTelemetry,
          );
    return manage(trooper);
  }

  Iterable<LifecycleAware> _allLifecycleChildren({
    bool reversed = false,
  }) sync* {
    final seen = <LifecycleAware>{};
    final first = reversed ? extraLifecycleChildren.reversed : _managedChildren;
    final second = reversed
        ? _managedChildren.reversed
        : extraLifecycleChildren;
    for (final child in first) {
      if (seen.add(child)) yield child;
    }
    for (final child in second) {
      if (seen.add(child)) yield child;
    }
  }

  Iterable<Invalidatable> _allInvalidatables() sync* {
    final seen = <Invalidatable>{};
    for (final inv in _managedInvalidatables) {
      if (seen.add(inv)) yield inv;
    }
    for (final inv in extraInvalidatables) {
      if (seen.add(inv)) yield inv;
    }
  }

  /// Invalidates all managed [Invalidatable] child components and [extraInvalidatables].
  @override
  void invalidate() {
    for (final target in _allInvalidatables()) {
      try {
        target.invalidate();
      } catch (error, stackTrace) {
        // Report, but keep invalidating the remaining targets.
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }

  /// Clears the default cache store, propagates clearAll to keyed troopers, and invalidates all managed troopers.
  ///
  /// Persisted L2 entries of every managed namespace are removed as well,
  /// including entries written in earlier sessions, so `clearAll()` on logout
  /// leaves no user data in storage.
  void clearAll() {
    defaultCache?.clear();
    for (final child in _allLifecycleChildren()) {
      if (child is KeyedQueryTrooper) {
        child.clearAll().ignore();
      } else if (child is KeyedLocalTrooper) {
        child.clearAll().ignore();
      } else if (child is KeyedStreamTrooper) {
        child.clearAll().ignore();
      }
    }
    invalidate();
  }

  /// Complete purge of all caches and managed state.
  @pragma('vm:prefer-inline')
  void executeOrder66() => clearAll();

  /// Initializes this controller via [onInit], followed by all managed
  /// [LifecycleAware] child components and [extraLifecycleChildren].
  @override
  FutureOr<void> initialize() async {
    final initResult = onInit();
    if (initResult is Future) {
      await initResult;
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final child in _allLifecycleChildren()) {
      try {
        final result = child.initialize();
        if (result is Future) {
          await result;
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Pauses this controller via [onPause], followed by all managed
  /// [LifecycleAware] child components and [extraLifecycleChildren].
  @override
  FutureOr<void> pause() async {
    defaultCache?.pause();
    final pauseResult = onPause();
    if (pauseResult is Future) {
      await pauseResult;
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final child in _allLifecycleChildren()) {
      try {
        final result = child.pause();
        if (result is Future) {
          await result;
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Resumes this controller via [onResume], followed by all managed
  /// [LifecycleAware] child components and [extraLifecycleChildren].
  @override
  FutureOr<void> resume() async {
    final resumeResult = onResume();
    if (resumeResult is Future) {
      await resumeResult;
    }
    defaultCache?.resume();

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final child in _allLifecycleChildren()) {
      try {
        final result = child.resume();
        if (result is Future) {
          await result;
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Recovers this controller via [onRecover], followed by all managed
  /// [LifecycleAware] child components and [extraLifecycleChildren].
  @override
  FutureOr<void> recover() async {
    final recoverResult = onRecover();
    if (recoverResult is Future) {
      await recoverResult;
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final child in _allLifecycleChildren()) {
      try {
        final result = child.recover();
        if (result is Future) {
          await result;
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Propagates dependency changes via [onDependenciesChanged], followed by
  /// all managed [LifecycleAware] child components and [extraLifecycleChildren].
  @override
  FutureOr<void> didChangeDependencies() async {
    final depResult = onDependenciesChanged();
    if (depResult is Future) {
      await depResult;
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final child in _allLifecycleChildren()) {
      try {
        final result = child.didChangeDependencies();
        if (result is Future) {
          await result;
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Disposes this controller via [onDispose], then disposes all managed
  /// children and [extraLifecycleChildren] in reverse registration order (LIFO),
  /// followed by shared orchestrator, mutation queue, and cache store.
  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      final disposeResult = onDispose();
      if (disposeResult is Future) {
        await disposeResult;
      }
    } catch (e, st) {
      firstError ??= e;
      firstStackTrace ??= st;
    }

    final childrenToDispose = _allLifecycleChildren(reversed: true).toList();
    _managedChildren.clear();
    _managedInvalidatables.clear();

    for (final child in childrenToDispose) {
      try {
        final result = child.dispose();
        if (result is Future) {
          await result;
        }
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }

    try {
      await defaultQueryQueue?.dispose();
    } catch (e, st) {
      firstError ??= e;
      firstStackTrace ??= st;
    }

    try {
      await defaultMutationQueue?.dispose();
    } catch (e, st) {
      firstError ??= e;
      firstStackTrace ??= st;
    }

    try {
      await defaultCache?.dispose();
    } catch (e, st) {
      firstError ??= e;
      firstStackTrace ??= st;
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
