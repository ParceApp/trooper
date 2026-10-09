import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/trooper.dart';
import 'package:trooper_bloc/src/match_result.dart';
import 'package:trooper_bloc/src/sources/watched.dart';

/// Mixin orchestrating reactive Trooper sources, snapshot-locking, microtask batching,
/// and fallback error/loading cascades.
///
/// Shared between `Tloc` (BLoC) and `Tubit` (Cubit).
mixin TrooperSources<S> {
  final List<WatchedHandle<dynamic, Parameter>> _managedHandles = [];
  bool _isDeriveScheduled = false;
  int _generation = 0;
  bool _initialized = false;

  /// The list of watched source handles whose state changes trigger [matchSources].
  ///
  /// Subclasses should declare their sources using `late final` fields or inline assignment:
  /// ```dart
  /// late final user = watch(store.users[id]);
  /// late final settings = watch(store.settings);
  ///
  /// @override
  /// List<Watched<Object?>> get sources => [user, settings];
  /// ```
  List<Watched<Object?>> get sources => const [];

  /// Evaluates current source snapshots and performs state transitions.
  ///
  /// Return `MatchResult.handled` (or `.handled`) if a state was emitted.
  /// Return `MatchResult.unhandled` (or `.unhandled`) to delegate to the fallback cascade:
  /// - If any source is in [DataError], [onAnyError] is invoked.
  /// - If any source is in [DataLoading] or [DataInitial], [onAnyLoading] is invoked.
  ///
  /// **Snapshot-Locking Guarantee:**
  /// During execution of [matchSources], every `handle.state` returns an immutable frozen
  /// snapshot taken at the start of the evaluation cycle. Asynchronous operations (`await`)
  /// will never see mutated source states within the same run.
  ///
  /// If newer data arrives while awaiting asynchronous operations, the outdated run is
  /// automatically aborted (restartable concurrency) and a fresh cycle is scheduled.
  FutureOr<MatchResult> matchSources(Emit<S> emit);

  /// Fallback handler invoked when [matchSources] returns [MatchResult.unhandled]
  /// and at least one watched source has not loaded data yet.
  void onAnyLoading(Emit<S> emit) {}

  /// Fallback handler invoked when [matchSources] returns [MatchResult.unhandled]
  /// and at least one watched source is in a [DataError] state, or [matchSources] throws.
  void onAnyError(
    Object error,
    StackTrace? stackTrace,
    Emit<S> emit,
  ) {}

  /// Convenient shortcut property returning [MatchResult.handled].
  MatchResult get handled => MatchResult.handled;

  /// Convenient shortcut property returning [MatchResult.unhandled].
  MatchResult get unhandled => MatchResult.unhandled;

  /// Watches an [Accessor].
  ///
  /// If [parameter] is omitted or `null`:
  /// - If `P` is `()`, defaults to `const ()`.
  /// - Otherwise, passively listens to the underlying resource stream without triggering an initial fetch.
  ///
  /// Any background fetch, refresh, or trigger on the accessor (regardless of parameter)
  /// will emit on this stream and trigger [matchSources].
  DynamicWatched<T, P> watch<T, P extends Parameter>(
    Accessor<T, P> accessor, [
    P? parameter,
  ]) {
    final effectiveParam = parameter ?? (P == const ().runtimeType ? const () as P : null);
    final handle = WatchedHandle<T, P>(
      accessor: accessor,
      parameter: effectiveParam,
      onUpdate: _onSourceUpdate,
    );
    _managedHandles.add(handle);
    if (_initialized) {
      handle.attach();
    }
    return handle;
  }

  /// Watches an [Accessor] with an explicit [parameter].
  ///
  /// Convenience alias for `watch(accessor, parameter)`.
  DynamicWatched<T, P> watchWith<T, P extends Parameter>(
    Accessor<T, P> accessor,
    P parameter,
  ) =>
      watch<T, P>(accessor, parameter);

  List<Watched<Object?>> _cachedSources = const [];

  /// Initializes all declared [sources] and evaluates initial state.
  ///
  /// Automatically invoked during construction of `Tloc` and `Tubit`.
  @protected
  void initializeSources() {
    if (_initialized) return;
    _initialized = true;

    // Reading the sources getter ensures all late final fields are instantiated
    _cachedSources = List.unmodifiable(sources);

    for (final handle in _managedHandles) {
      handle.attach();
    }

    _scheduleSourceUpdate();
  }

  void _onSourceUpdate(Watched<dynamic> source) {
    _scheduleSourceUpdate();
  }

  /// Schedules source evaluation in the next microtask.
  ///
  /// Multiple synchronous updates from different sources within the same
  /// event-loop turn are coalesced into a single evaluation cycle.
  void _scheduleSourceUpdate() {
    if (isClosed || _isDeriveScheduled) return;
    _isDeriveScheduled = true;
    scheduleMicrotask(_processScheduledSourceUpdate);
  }

  void _processScheduledSourceUpdate() {
    if (isClosed) return;
    _isDeriveScheduled = false;
    triggerSourceEvaluation();
  }

  /// Subclass hook called when a debounced source evaluation should be executed.
  ///
  /// `Tloc` dispatches an internal BLoC event, while `Tubit` executes immediately.
  @protected
  void triggerSourceEvaluation();

  /// Executes source evaluation with snapshot locking and generation tracking.
  @protected
  Future<void> executeSourceEvaluation(void Function(S state) emitTarget) async {
    if (isClosed) return;
    final currentGen = ++_generation;

    // 1. Lock snapshots on all managed handles
    for (final handle in _managedHandles) {
      handle.lockSnapshot();
    }

    // 2. Create guarded emitter
    void guardedEmit(S state) {
      if (currentGen == _generation && !isClosed) {
        emitTarget(state);
      }
    }

    try {
      final matchResultFuture = matchSources(guardedEmit);
      if (matchResultFuture is Future<MatchResult>) {
        final result = await matchResultFuture;
        if (currentGen == _generation && !isClosed) {
          _processMatchResult(result, guardedEmit);
        }
      } else {
        _processMatchResult(matchResultFuture, guardedEmit);
      }
    } catch (error, stackTrace) {
      if (currentGen == _generation && !isClosed) {
        onAnyError(error, stackTrace, guardedEmit);
      }
      onSourceException(error, stackTrace);
    } finally {
      // 3. Unlock snapshots once evaluation completes
      for (final handle in _managedHandles) {
        handle.unlockSnapshot();
      }
    }
  }

  void _processMatchResult(
    MatchResult result,
    void Function(S state) emitTarget,
  ) {
    if (result.isHandled) {
      return;
    }

    // Evaluate fallback cascade
    final currentSources =
        _cachedSources.isNotEmpty ? _cachedSources : _managedHandles;

    // 1. Error check
    for (final s in currentSources) {
      final state = s.state;
      if (state is DataError) {
        onAnyError(state.error, state.stackTrace, emitTarget);
        return;
      }
    }

    // 2. Loading check
    for (final s in currentSources) {
      final state = s.state;
      if (state is DataLoading || state is DataInitial) {
        onAnyLoading(emitTarget);
        return;
      }
    }
  }

  /// Refreshes all watched sources concurrently.
  Future<void> refreshAll() async {
    final futures = <Future<dynamic>>[];
    for (final handle in _managedHandles) {
      futures.add(handle.refresh());
    }
    await Future.wait(futures);
  }

  /// Manually forces a new execution of [matchSources].
  void rederive() {
    _scheduleSourceUpdate();
  }

  /// Pauses all watched sources.
  @protected
  void pauseSources() {
    for (final handle in _managedHandles) {
      handle.pause();
    }
  }

  /// Resumes all watched sources and checks for updates.
  @protected
  void resumeSources() {
    for (final handle in _managedHandles) {
      handle.resume();
    }
    _scheduleSourceUpdate();
  }

  /// Cancels all stream subscriptions for watched sources.
  @protected
  Future<void> disposeSources() async {
    _isDeriveScheduled = false;
    _generation++;
    for (final handle in _managedHandles) {
      await handle.dispose();
    }
    _managedHandles.clear();
  }

  /// Subclass hook checking whether the component is closed.
  bool get isClosed;

  /// Subclass hook invoked when an unhandled exception occurs.
  @protected
  void onSourceException(Object error, StackTrace stackTrace);
}
