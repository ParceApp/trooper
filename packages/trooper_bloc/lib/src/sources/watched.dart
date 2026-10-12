import 'dart:async';
import 'package:trooper/trooper.dart';

/// Callback invoked when a [Watched] source receives a stream event or its configuration changes.
typedef WatchedUpdateCallback = void Function(Watched<dynamic> source);

/// Strongly-typed reactive handle over a watched [Accessor].
///
/// Created by calling `watch(accessor)` inside a `Tloc` or `Tubit`.
///
/// Exposes synchronous snapshot access via [state] for idiomatic Dart 3.5+ pattern matching:
/// ```dart
/// late final user = watch(store.users[userId]);
///
/// @override
/// FutureOr<MatchResult> matchSources(Emit<ProfileState> emit) {
///   switch (user.state) {
///     case DataLoaded(:final data):
///       emit(ProfileLoadedState(data));
///       return .handled;
///   }
///   return .unhandled;
/// }
/// ```
abstract interface class Watched<T> {
  /// The current snapshot state of this source.
  ///
  /// **Snapshot-Locking Guarantee:**
  /// During execution of `matchSources`, this getter returns an immutable frozen snapshot
  /// captured at the start of the execution cycle. Even if background network or cache events
  /// arrive while awaiting asynchronous operations, [state] remains completely stable
  /// within that execution context.
  StatefulData<T> get state;

  /// Synchronously returns whether this source currently holds loaded or refreshing data.
  bool get hasData;

  /// Synchronously returns whether this source is actively loading or refreshing.
  bool get isLoading;

  /// Synchronously returns whether this source is in an error state.
  bool get isError;

  /// Synchronously returns the unwrapped data payload if loaded, or `null` otherwise.
  T? get dataOrNull;
}

/// Concrete implementation of [Watched] supporting snapshot-locking and lifecycle events.
class WatchedHandle<T, P extends Parameter> implements Watched<T> {
  /// Creates a [WatchedHandle] bound to [accessor] with an optional [initialParameter].
  WatchedHandle({
    required Accessor<T, P> accessor,
    required this._onUpdate,
    this.initialParameter,
    this.eager = false,
  }) : _accessor = accessor,
       _liveState = accessor.current();

  final Accessor<T, P> _accessor;

  /// The initial parameter passed when watching, or `null` if watched passively.
  final P? initialParameter;

  /// Whether watching is eager (triggers initial fetch).
  final bool eager;
  final WatchedUpdateCallback _onUpdate;

  StreamSubscription<StatefulData<T>>? _subscription;
  StatefulData<T> _liveState = const DataInitial();
  StatefulData<T>? _snapshotState;

  bool _isDisposed = false;
  bool _isPaused = false;

  /// The underlying [Accessor] being watched.
  Accessor<T, P> get accessor => _accessor;

  /// The parameter passed when watching, or `null` if watched passively.
  P? get parameter => initialParameter;

  /// The authoritative live state of the underlying accessor.
  StatefulData<T> get liveState => _liveState;

  @override
  StatefulData<T> get state => _snapshotState ?? _liveState;

  @override
  bool get hasData => state.isLoaded;

  @override
  bool get isLoading => state.isLoading;

  @override
  bool get isError => state.isError;

  @override
  T? get dataOrNull => state.dataOrNull;

  /// Freezes [state] to the current [liveState] for the duration of a `matchSources` run.
  void lockSnapshot() {
    _snapshotState = _liveState;
  }

  /// Releases the frozen snapshot lock, allowing [state] to reflect subsequent live updates.
  void unlockSnapshot() {
    _snapshotState = null;
  }

  /// Begins listening to the underlying [Accessor].
  void attach() {
    if (_isDisposed || _subscription != null) return;
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = null;

    final stream = _accessor.watch(
      initialParameter: initialParameter,
      eager: eager,
    );
    _liveState = _accessor.current();

    _subscription = stream.listen(
      (data) {
        _liveState = data;
        if (!_isDisposed && !_isPaused) {
          _onUpdate(this);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _liveState = StatefulData<T>.error(error, stackTrace: stackTrace);
        if (!_isDisposed && !_isPaused) {
          _onUpdate(this);
        }
      },
    );
  }

  /// Pauses event propagation from this handle.
  void pause() {
    _isPaused = true;
    _subscription?.pause();
  }

  /// Resumes event propagation and synchronizes state.
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    _subscription?.resume();
    final fresh = _accessor.current();
    if (_liveState != fresh) {
      _liveState = fresh;
    }
  }

  /// Cancels stream subscriptions and marks this handle as disposed.
  Future<void> dispose() async {
    _isDisposed = true;
    _snapshotState = null;
    final sub = _subscription;
    _subscription = null;
    await sub?.cancel();
  }
}
