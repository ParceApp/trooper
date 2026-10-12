import 'dart:async';
import 'package:trooper/trooper.dart';

/// Test utility creating an in-memory [Accessor] whose states can be synchronously
/// and reactively manipulated during unit tests.
class FakeAccessor<T, P extends Parameter> implements Accessor<T, P> {
  /// Creates a [FakeAccessor] with optional [initialData] or [initialState].
  FakeAccessor({
    T? initialData,
    StatefulData<T>? initialState,
  }) : _state = initialState ??
            (initialData != null
                ? StatefulData.loaded(initialData)
                : StatefulData.initial()) {
    _streamController = StreamController<StatefulData<T>>.broadcast();
  }

  late final StreamController<StatefulData<T>> _streamController;
  StatefulData<T> _state;

  /// Counter tracking how many times [get] was called.
  int getCount = 0;

  /// Counter tracking how many times [refresh] was called.
  int refreshCount = 0;

  /// Counter tracking how many times [trigger] was called.
  int triggerCount = 0;

  /// Counter tracking how many times [invalidate] was called.
  int invalidateCount = 0;

  /// Counter tracking how many times [watch] was called.
  int watchCount = 0;

  @override
  StatefulStream<T> get stream => StatefulStream<T>(
        _streamController.stream,
        currentStateProvider: () => _state,
      );

  @override
  StatefulData<T> current([P? parameter]) => _state;

  @override
  T? currentData([P? parameter]) => _state.dataOrNull;

  @override
  StatefulStream<T> watch([P? parameter, bool eager = true]) {
    watchCount++;
    return stream;
  }

  @override
  Future<T> get([P? parameter, bool forceRefresh = false]) async {
    getCount++;
    final data = _state.dataOrNull;
    if (data != null && !forceRefresh) return data;
    throw StateError('FakeAccessor has no data to return for get()');
  }

  @override
  Future<T> refresh([P? parameter]) async {
    refreshCount++;
    final data = _state.dataOrNull;
    if (data != null) return data;
    throw StateError('FakeAccessor has no data to return for refresh()');
  }

  @override
  void trigger([P? parameter, bool forceRefresh = false]) {
    triggerCount++;
  }

  @override
  void invalidate() {
    invalidateCount++;
    emitState(StatefulData<T>.initial());
  }

  /// Manually pushes a new [state] to all active stream listeners.
  void emitState(StatefulData<T> state) {
    _state = state;
    if (!_streamController.isClosed) {
      _streamController.add(state);
    }
  }

  /// Convenience method to push a [DataLoaded] state.
  void emitData(T data, {DataMetadata? metadata}) =>
      emitState(StatefulData.loaded(data, metadata: metadata));

  /// Convenience method to push a [DataLoading] state.
  void emitLoading({double? progress}) =>
      emitState(StatefulData.loading(progress: progress));

  /// Convenience method to push a [DataRefreshing] state.
  void emitRefreshing(T data, {double? progress, DataMetadata? metadata}) =>
      emitState(StatefulData.refreshing(data, progress: progress, metadata: metadata));

  /// Convenience method to push a [DataError] state.
  void emitError(Object error, {StackTrace? stackTrace, T? staleData}) =>
      emitState(StatefulData.error(error, stackTrace: stackTrace, staleData: staleData));

  /// Manually pushes an unhandled error to the underlying stream.
  void emitStreamError(Object error, [StackTrace? stackTrace]) {
    if (!_streamController.isClosed) {
      _streamController.addError(error, stackTrace);
    }
  }

  /// Closes the internal broadcast controller.
  Future<void> close() => _streamController.close();
}
