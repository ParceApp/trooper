import 'dart:async';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';

/// A broadcast controller managing a re-playable [StatefulStream].
///
/// Combines broadcast streaming with a BehaviorSubject pattern:
/// whenever a new listener subscribes, it **immediately** receives the [currentState],
/// followed by all future transitions.
///
/// Implements [LifecycleAware] to easily integrate into lifecycle management.
///
/// ### Example:
/// ```dart
/// final controller = StatefulStreamController<String>();
///
/// controller.emitData('First Value');
///
/// // Later subscriber gets 'First Value' synchronously as its first event:
/// controller.stream.listen((state) {
///   print('Received: ${state.dataOrNull}');
/// });
///
/// controller.emitLoading();
/// ```
class StatefulStreamController<T> with LifecycleAware {
  /// Creates a [StatefulStreamController] with an optional [initialState] (defaults to [DataInitial]).
  ///
  /// If `distinct` is `true` (default), duplicate consecutive identical states
  /// will not be emitted to the stream.
  StatefulStreamController({
    StatefulData<T> initialState = const DataInitial(),
    this._distinct = true,
    void Function()? onListen,
    void Function()? onCancel,
  }) : _currentState = initialState {
    _broadcastController = StreamController<StatefulData<T>>.broadcast(
      onListen: onListen,
      onCancel: onCancel,
    );

    // Multi-stream that replays currentState to every new subscriber
    final multiStream = Stream<StatefulData<T>>.multi((listener) {
      listener.addSync(_currentState);
      final sub = _broadcastController.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    }, isBroadcast: true);

    _statefulStream = StatefulStream<T>(
      multiStream,
      currentStateProvider: () => _currentState,
      rawBroadcastStream: _broadcastController.stream,
    );
  }

  late final StreamController<StatefulData<T>> _broadcastController;
  late final StatefulStream<T> _statefulStream;
  StatefulData<T> _currentState;
  final bool _distinct;

  /// The current state held by this controller.
  StatefulData<T> get currentState => _currentState;

  /// The current data payload, or `null` if no data is loaded.
  T? get currentData => _currentState.dataOrNull;

  /// Returns `true` if valid data is currently available in [currentState].
  bool get isLoaded => _currentState.isLoaded;

  /// Returns `true` if an operation is actively in-flight in [currentState].
  bool get isLoading => _currentState.isLoading;

  /// Returns `true` if [currentState] is an error state.
  bool get isError => _currentState.isError;

  /// Returns `true` if [currentState] is a background refresh.
  bool get isRefreshing => _currentState.isRefreshing;

  /// The re-playable [StatefulStream] exposed to consumers.
  StatefulStream<T> get stream => _statefulStream;

  /// Whether the controller is closed.
  bool get isClosed => _broadcastController.isClosed;

  /// Whether this controller currently has active listeners subscribed to its stream.
  bool get hasListeners =>
      !_broadcastController.isClosed && _broadcastController.hasListener;

  /// Emits a new [state] to all active listeners.
  ///
  /// If `distinct` was enabled in constructor and [state] is equal to [currentState],
  /// the emission is skipped.
  void emit(StatefulData<T> state) {
    if (_broadcastController.isClosed) return;
    if (_distinct && _currentState == state) return;

    _currentState = state;
    _broadcastController.add(state);
  }

  /// Convenience method to emit a [DataLoaded] state.
  void emitData(T data, {DataMetadata? metadata}) =>
      emit(DataLoaded<T>(data, metadata: metadata));

  /// Convenience method to emit a [DataRefreshing] state (SWR).
  void emitRefreshing(T data, {double? progress, DataMetadata? metadata}) =>
      emit(DataRefreshing<T>(data, progress: progress, metadata: metadata));

  /// Convenience method to emit a [DataLoading] state.
  void emitLoading({double? progress}) =>
      emit(DataLoading<T>(progress: progress));

  /// Convenience method to emit a [DataError] state.
  void emitError(Object error, {StackTrace? stackTrace, T? staleData}) =>
      emit(DataError<T>(error, stackTrace: stackTrace, staleData: staleData));

  /// Convenience method to reset to [DataInitial].
  void emitInitial() => emit(DataInitial<T>());

  /// Closes the controller and terminates the stream.
  Future<void> close() => _broadcastController.close();

  @override
  Future<void> dispose() => close();
}
