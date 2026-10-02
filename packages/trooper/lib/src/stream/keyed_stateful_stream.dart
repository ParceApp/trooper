import 'dart:async';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';

/// A reactive stream orchestrator managing multiple entity keys of type [K],
/// where each key holds an independent [StatefulData] state of type [T].
///
/// Provides both fine-grained single-key streams via [streamOf] and aggregate
/// collection streams via [watchAll] and [watchKeys].
///
/// Implements [LifecycleAware] to easily integrate into lifecycle management.
///
/// ### Example:
/// ```dart
/// final keyed = KeyedStatefulStream<String, Lecture>();
///
/// // Watch single lecture:
/// keyed.streamOf('math-101').dataStream.listen((lecture) {
///   print('Math 101 updated: ${lecture.title}');
/// });
///
/// // Watch all lectures together:
/// keyed.watchAll().listen((map) {
///   print('Total entries in cache: ${map.length}');
/// });
///
/// keyed.emitData('math-101', Lecture(id: 'math-101', title: 'Calculus'));
/// ```
class KeyedStatefulStream<K, T> with LifecycleAware {
  /// Creates an empty [KeyedStatefulStream].
  KeyedStatefulStream({this._distinct = true}) {
    _allController = StreamController<Map<K, StatefulData<T>>>.broadcast(
      sync: true,
    );
    _keysController = StreamController<Set<K>>.broadcast(sync: true);
  }

  final bool _distinct;
  final Map<K, StatefulStreamController<T>> _controllers = {};
  late final StreamController<Map<K, StatefulData<T>>> _allController;
  late final StreamController<Set<K>> _keysController;
  bool _isClosed = false;

  bool _isEmittingAll = false;
  final List<Map<K, StatefulData<T>>> _pendingAllEvents = [];

  bool _isEmittingKeys = false;
  final List<Set<K>> _pendingKeysEvents = [];

  void _notifyAll() {
    if (_isClosed || !_allController.hasListener) return;
    if (_isEmittingAll) {
      _pendingAllEvents.add(currentStates);
      return;
    }
    _isEmittingAll = true;
    try {
      _allController.add(currentStates);
      while (_pendingAllEvents.isNotEmpty) {
        if (_isClosed || _allController.isClosed) break;
        _allController.add(_pendingAllEvents.removeAt(0));
      }
    } finally {
      _isEmittingAll = false;
    }
  }

  void _notifyKeys() {
    if (_isClosed || !_keysController.hasListener) return;
    if (_isEmittingKeys) {
      _pendingKeysEvents.add(activeKeys);
      return;
    }
    _isEmittingKeys = true;
    try {
      _keysController.add(activeKeys);
      while (_pendingKeysEvents.isNotEmpty) {
        if (_isClosed || _keysController.isClosed) break;
        _keysController.add(_pendingKeysEvents.removeAt(0));
      }
    } finally {
      _isEmittingKeys = false;
    }
  }

  /// Returns the set of currently tracked keys.
  Set<K> get activeKeys => Set.unmodifiable(_controllers.keys);

  /// Returns the total number of tracked keys.
  int get count => _controllers.length;

  /// Whether this keyed stream manager has been closed.
  bool get isClosed => _isClosed;

  /// Whether any child stream or aggregate stream currently has active listeners.
  bool get hasListeners =>
      (!_allController.isClosed && _allController.hasListener) ||
      (!_keysController.isClosed && _keysController.hasListener) ||
      _controllers.values.any((c) => c.hasListeners);

  /// Returns `true` if the stream for [key] currently has active listeners.
  bool hasKeyListeners(K key) => _controllers[key]?.hasListeners ?? false;

  /// Returns `true` if [key] is currently tracked.
  bool containsKey(K key) => _controllers.containsKey(key);

  /// Returns the current state for [key] synchronously.
  ///
  /// If the key has not been accessed or emitted yet, returns [DataInitial].
  StatefulData<T> stateOf(K key) =>
      _controllers[key]?.currentState ?? const DataInitial();

  /// Returns the current data payload for [key] synchronously, or `null`.
  T? dataOf(K key) => stateOf(key).dataOrNull;

  /// Returns an immutable snapshot map of all currently tracked keys and their states.
  Map<K, StatefulData<T>> get currentStates => Map.unmodifiable({
    for (final e in _controllers.entries) e.key: e.value.currentState,
  });

  /// Returns a map containing only keys that have valid loaded data.
  Map<K, T> get currentDataMap {
    final result = <K, T>{};
    for (final entry in _controllers.entries) {
      final data = entry.value.currentData;
      if (data != null) {
        result[entry.key] = data;
      }
    }
    return Map.unmodifiable(result);
  }

  /// Returns an isolated [StatefulStream] for the given [key].
  ///
  /// The stream is lazily initialized if it does not yet exist.
  StatefulStream<T> streamOf(K key) {
    final isNew = !_controllers.containsKey(key);
    final controller = _getOrCreateController(key);
    if (isNew) {
      _notifyKeys();
      _notifyAll();
    }
    return controller.stream;
  }

  /// Returns a stream emitting the entire map of all keys and their states
  /// whenever any single key's state changes.
  ///
  /// Immediately delivers the current snapshot to new subscribers.
  Stream<Map<K, StatefulData<T>>> watchAll() =>
      Stream<Map<K, StatefulData<T>>>.multi((listener) {
        listener.addSync(currentStates);
        final sub = _allController.stream.listen(
          listener.addSync,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = sub.cancel;
      }, isBroadcast: true);

  /// Returns a stream emitting the set of tracked keys whenever keys are added or removed.
  Stream<Set<K>> watchKeys() => Stream<Set<K>>.multi((listener) {
    listener.addSync(activeKeys);
    final sub = _keysController.stream.listen(
      listener.addSync,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = sub.cancel;
  }, isBroadcast: true);

  /// Emits a new [state] for the given [key].
  void emit(K key, StatefulData<T> state) {
    if (_isClosed) return;
    final isNewKey = !_controllers.containsKey(key);
    final controller = _getOrCreateController(key);
    final previousState = controller.currentState;

    controller.emit(state);

    // Notify aggregate listeners if state changed or new key added
    if (isNewKey || previousState != state) {
      if (isNewKey) {
        _notifyKeys();
      }
      _notifyAll();
    }
  }

  /// Convenience method to emit a [DataLoaded] state for [key].
  void emitData(K key, T data, {DataMetadata? metadata}) =>
      emit(key, DataLoaded<T>(data, metadata: metadata));

  /// Convenience method to emit a [DataRefreshing] state (SWR) for [key].
  void emitRefreshing(
    K key,
    T data, {
    double? progress,
    DataMetadata? metadata,
  }) => emit(
    key,
    DataRefreshing<T>(data, progress: progress, metadata: metadata),
  );

  /// Convenience method to emit a [DataLoading] state for [key].
  void emitLoading(K key, {double? progress}) =>
      emit(key, DataLoading<T>(progress: progress));

  /// Convenience method to emit a [DataError] state for [key].
  void emitError(K key, Object error, {StackTrace? stackTrace, T? staleData}) =>
      emit(
        key,
        DataError<T>(error, stackTrace: stackTrace, staleData: staleData),
      );

  /// Convenience method to emit a [DataInitial] state for [key].
  void emitInitial(K key) => emit(key, DataInitial<T>());

  /// Removes [key] from tracking, closes its isolated stream, and notifies aggregate listeners.
  Future<void> removeKey(K key) async {
    if (_isClosed) return;
    final controller = _controllers.remove(key);
    if (controller != null) {
      _notifyKeys();
      _notifyAll();
      await controller.close();
    }
  }

  /// Clears all tracked keys, resets the collection to empty, and awaits closing of all child streams.
  Future<void> clearAll() async {
    if (_isClosed) return;
    final toClose = _controllers.values.toList();
    _controllers.clear();
    _notifyKeys();
    _notifyAll();
    await Future.wait(toClose.map((c) => c.close()));
  }

  /// Closes all per-key streams and aggregate stream controllers.
  Future<void> close() async {
    _isClosed = true;
    _pendingAllEvents.clear();
    _pendingKeysEvents.clear();
    final toClose = _controllers.values.toList();
    _controllers.clear();
    for (final controller in toClose) {
      await controller.close();
    }
    if (_isEmittingAll) {
      scheduleMicrotask(() => _allController.close());
    } else {
      await _allController.close();
    }
    if (_isEmittingKeys) {
      scheduleMicrotask(() => _keysController.close());
    } else {
      await _keysController.close();
    }
  }

  @override
  Future<void> dispose() => close();

  StatefulStreamController<T> _getOrCreateController(K key) => _controllers
      .putIfAbsent(key, () => StatefulStreamController<T>(distinct: _distinct));
}
