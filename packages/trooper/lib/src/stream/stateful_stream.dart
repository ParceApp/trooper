import 'dart:async';
import 'package:trooper/src/state/stateful_data.dart';

/// A specialized [Stream] emitting [StatefulData] transitions with synchronous state inspection
/// and convenient filtered sub-streams.
///
/// Extends [StreamView] to provide standard [Stream] methods while exposing
/// [currentState], [currentData], [dataStream], [errorStream], and [loadingStream].
///
/// ### Example:
/// ```dart
/// final stream = controller.allLectures.stream;
///
/// // Synchronous inspection:
/// print('Currently loaded: ${stream.isLoaded}');
///
/// // Subscribe only to successful data updates:
/// stream.dataStream.listen((lectures) {
///   print('Got ${lectures.length} lectures');
/// });
///
/// // Subscribe to loading changes (e.g. for a global spinner):
/// stream.loadingStream.listen((isLoading) {
///   print('Is loading: $isLoading');
/// });
/// ```
class StatefulStream<T> extends StreamView<StatefulData<T>> {
  /// Creates a [StatefulStream] wrapping an underlying [stream] with a state-reading supplier.
  StatefulStream(
    super.stream, {
    required this._currentStateProvider,
    this.rawBroadcastStream,
    this.skipInitialState = false,
  });

  /// Function supplying the current state synchronously.
  final StatefulData<T> Function() _currentStateProvider;

  /// The underlying broadcast stream without replayed initial events, if available.
  final Stream<StatefulData<T>>? rawBroadcastStream;

  /// Whether this stream skips replaying the initial [currentState] upon subscription.
  final bool skipInitialState;

  /// Returns a [StatefulStream] that skips replaying the [currentState] to new listeners.
  ///
  /// Subscribers to the returned stream will only receive transitions emitted *after* subscription.
  /// Synchronous inspection getters (e.g. [currentState], [currentData], [isLoaded]) continue
  /// to work identically.
  ///
  /// If this stream is already configured to skip current replay, calling this method returns the same instance.
  StatefulStream<T> skipCurrent() {
    if (skipInitialState) return this;

    final targetStream = rawBroadcastStream ?? skip(1);
    return StatefulStream<T>(
      targetStream,
      currentStateProvider: _currentStateProvider,
      skipInitialState: true,
    );
  }

  /// Returns the current state synchronously without waiting for the next stream event.
  StatefulData<T> get currentState => _currentStateProvider();

  /// Returns the current data payload synchronously, or `null` if no data is loaded.
  T? get currentData => currentState.dataOrNull;

  /// Returns `true` if this stream is currently in its initial state synchronously.
  bool get isInitial => currentState.isInitial;

  /// Returns `true` if valid data is currently available synchronously.
  bool get isLoaded => currentState.isLoaded;

  /// Returns `true` if an operation is actively in-flight synchronously.
  bool get isLoading => currentState.isLoading;

  /// Returns `true` if this stream is currently in an error state synchronously.
  bool get isError => currentState.isError;

  /// Returns `true` if this stream is currently performing a background refresh synchronously.
  bool get isRefreshing => currentState.isRefreshing;

  /// A sub-stream that emits only the unwrapped data payload [T] when data is loaded.
  ///
  /// Filters out [DataInitial], [DataLoading], and [DataError] states. Emits for both
  /// [DataLoaded] and [DataRefreshing].
  Stream<T> get dataStream =>
      where((s) => s.isLoaded).map((s) => s.dataOrNull as T);

  /// A sub-stream that emits only error objects when a [DataError] occurs.
  Stream<Object> get errorStream =>
      where((s) => s.isError).map((s) => s.errorOrNull!);

  /// A sub-stream that emits boolean transitions of [StatefulData.isLoading].
  ///
  /// Deduplicated with [Stream.distinct] so listeners only receive updates
  /// when the loading status actually flips.
  Stream<bool> get loadingStream => map((s) => s.isLoading).distinct();

  /// Transforms the data payload of every [DataLoaded] and [DataRefreshing] event
  /// using the provided [mapper] function.
  Stream<StatefulData<R>> mapData<R>(R Function(T data) mapper) => map(
    (s) => switch (s) {
      DataInitial<T>() => DataInitial<R>(),
      DataLoading<T>(:final progress) => DataLoading<R>(progress: progress),
      DataRefreshing<T>(:final data, :final progress, :final metadata) =>
        DataRefreshing<R>(mapper(data), progress: progress, metadata: metadata),
      DataLoaded<T>(:final data, :final metadata) => DataLoaded<R>(
        mapper(data),
        metadata: metadata,
      ),
      DataError<T>(error: final err, :final stackTrace, :final staleData) =>
        DataError<R>(
          err,
          stackTrace: stackTrace,
          staleData: staleData != null ? mapper(staleData) : null,
        ),
    },
  );
}
