import 'dart:async';

/// An interface and mixin for objects participating in a structured lifecycle.
///
/// Implement or mix in this class on any service, stream controller, cache,
/// or custom component that needs to react to lifecycle events.
///
/// All methods provide empty default implementations returning [FutureOr<void>],
/// allowing implementors to override only the lifecycle hooks they need, either
/// synchronously (`void`) or asynchronously (`Future<void>`).
///
/// ### Example:
/// ```dart
/// class MyService with LifecycleAware {
///   StreamSubscription<void>? _sub;
///
///   @override
///   void initialize() {
///     // Setup resources
///   }
///
///   @override
///   void didChangeDependencies() {
///     // React to auth or environment changes
///   }
///
///   @override
///    void recover() {
///      // Recover state or refresh data after an error or offline period.
///      // Useful for network tracking or an basic try-again button on an error page.
///    }
///
///   @override
///   void pause() {
///     // Pause streams or timers if app is in background
///   }
///
///   @override
///   void resume() {
///     // Resume streams or timers if app is back in foreground
///   }
///
///   @override
///   Future<void> dispose() async {
///     await _sub?.cancel();
///   }
/// }
/// ```
abstract mixin class LifecycleAware {
  /// Called once when the component is registered or initialized.
  FutureOr<void> initialize() {}

  /// Called when parent dependencies or environment configuration change
  /// (e.g. auth token update, locale change, connection reset).
  FutureOr<void> didChangeDependencies() {}

  /// Called to recover state, re-establish lost connections, or refresh data
  /// after an error, offline period, or app resume.
  FutureOr<void> recover() {}

  /// Called when the component is temporarily paused (e.g. app sent to background).
  FutureOr<void> pause() {}

  /// Called when the component resumes from a paused state.
  FutureOr<void> resume() {}

  /// Releases resources, cancels subscriptions, and closes streams.
  ///
  /// Once disposed, the component should not be reused. Every Trooper type
  /// (troopers, mutations, `LoadMore`, `CacheStore`, the queues and
  /// `TrooperController`) follows the same contract after [dispose]:
  ///
  /// - Calls that load, write, emit, connect, execute or start observing
  ///   (`get`, `refresh`, `trigger`, `set…`, `update…`, `reset…`, `connect…`,
  ///   `execute`, `watch…`, `CacheStore.put`/`get`…) throw a [StateError];
  ///   methods returning a [Future] complete with it.
  /// - [dispose] itself is idempotent.
  /// - Snapshots such as `isDisposed`, `current()`, `currentData()` and
  ///   `currentStates` return the last known state.
  /// - `invalidate()`, [pause], [resume], [recover] and
  ///   [didChangeDependencies] (and cleanup such as `removeKey`, `clearAll`,
  ///   `disconnect`) do nothing, so invalidation cascades never fail because
  ///   one target is already disposed.
  FutureOr<void> dispose() {}
}
