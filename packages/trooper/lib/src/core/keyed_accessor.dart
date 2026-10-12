import 'dart:async';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/types/parameter.dart';

/// Unified consumer interface for getting, watching, and observing a keyed collection of resources.
///
/// Implements [Accessor] for the collection-wide `Map<K, T>`, allowing consumers to either
/// observe the entire map or query individual items by key.
///
/// ### Example:
/// ```dart
/// class CourseController extends TrooperController {
///   late final _courses = keyedQuery<int, Course, ()>(...);
///
///   // Expose read-only KeyedAccessor:
///   KeyedAccessor<int, Course, ()> get courses => _courses.accessor;
/// }
///
/// // Read single item by key:
/// final course = await controller.courses[42].get(());
///
/// // Watch single item by key:
/// controller.courses[42].watch(()).listen(...);
///
/// // Watch entire collection as a reactive Map:
/// controller.courses.watch(()).listen((state) {
///   print('All courses: ${state.dataOrNull}');
/// });
///
/// // Get current collection snapshot:
/// Map<int, Course> allCourses = controller.courses.currentDataMap;
/// ```
abstract interface class KeyedAccessor<K extends Object, T, P extends Parameter>
    implements Accessor<Map<K, T>, ()> {
  /// Returns a bound read-only [Accessor] scoped to entity [key].
  Accessor<T, P> operator [](K key);

  /// Returns a bound read-only [Accessor] scoped to entity [key].
  Accessor<T, P> key(K key);

  /// Invalidates the cache entry and state for [key] across all parameters.
  void invalidateKey(K key);

  /// Invalidates the cache entries and states for multiple [keys] across all parameters.
  void invalidateKeys(Iterable<K> keys);

  /// Reads values for multiple [keys] concurrently, returning a Map of results.
  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  });

  /// Forces fresh data fetches for multiple [keys] concurrently, bypassing cache freshness.
  Future<Map<K, T>> refreshKeys(Iterable<K> keys, P parameter);

  /// Triggers background fetches for multiple [keys] without waiting for results.
  void triggerKeys(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  });

  /// Reactively observes the state of all keys as a Map of [StatefulData].
  Stream<Map<K, StatefulData<T>>> watchAll();

  /// Reactively observes the set of active keys.
  Stream<Set<K>> watchKeys();

  /// Synchronously returns all currently loaded key-value pairs as an unmodifiable Map.
  Map<K, T> get currentDataMap;

  /// Synchronously returns all current key states.
  Map<K, StatefulData<T>> get currentStates;

  /// Returns the set of currently active keys.
  Set<K> get activeKeys;

  /// Returns the number of currently active keys.
  int get count;
}

/// Concrete, unmodifiable implementation of [KeyedAccessor].
class KeyedTrooperAccessor<K extends Object, T, P extends Parameter>
    implements KeyedAccessor<K, T, P> {
  /// Creates a [KeyedTrooperAccessor] delegating to the underlying [stream] and accessor callbacks.
  KeyedTrooperAccessor({
    required this.accessorFactory,
    required KeyedStatefulStream<K, T> stream,
    required this.onInvalidate,
    this.onInvalidateKey,
    this.onRead,
    this.onRefresh,
  }) : _keyedStream = stream;

  /// Factory resolving a single-key [Accessor].
  final Accessor<T, P> Function(K key) accessorFactory;

  /// Underlying keyed stream managing per-key state.
  final KeyedStatefulStream<K, T> _keyedStream;

  /// Callback to invalidate the collection.
  final void Function() onInvalidate;

  /// Optional callback to invalidate a single key across all parameters.
  final void Function(K key)? onInvalidateKey;

  /// Optional custom get handler for the entire map.
  final Future<Map<K, T>> Function()? onRead;

  /// Optional custom refresh handler for the entire map.
  final Future<Map<K, T>> Function()? onRefresh;

  @override
  Accessor<T, P> operator [](K key) => accessorFactory(key);

  @override
  Accessor<T, P> key(K key) => accessorFactory(key);

  @override
  void invalidateKey(K key) => onInvalidateKey?.call(key);

  @override
  void invalidateKeys(Iterable<K> keys) {
    for (final k in keys) {
      invalidateKey(k);
    }
  }

  @override
  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => this[k].get(parameter, forceRefresh: forceRefresh)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  Future<Map<K, T>> refreshKeys(Iterable<K> keys, P parameter) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => this[k].refresh(parameter)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  void triggerKeys(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) {
    for (final k in keys) {
      this[k].trigger(parameter, forceRefresh: forceRefresh);
    }
  }

  @override
  Map<K, T> get currentDataMap => _keyedStream.currentDataMap;

  @override
  Map<K, StatefulData<T>> get currentStates => _keyedStream.currentStates;

  @override
  Set<K> get activeKeys => _keyedStream.activeKeys;

  @override
  int get count => _keyedStream.count;

  @override
  Stream<Map<K, StatefulData<T>>> watchAll() => _keyedStream.watchAll();

  @override
  Stream<Set<K>> watchKeys() => _keyedStream.watchKeys();

  @override
  StatefulStream<Map<K, T>> get stream => StatefulStream<Map<K, T>>(
        _keyedStream.watchAll().map((_) => current(const ())),
        currentStateProvider: () => current(const ()),
      );

  @override
  StatefulStream<Map<K, T>> watch({() ? initialParameter, bool eager = false}) =>
      stream;

  @override
  Future<Map<K, T>> get(() parameter, {bool forceRefresh = false}) async {
    if (forceRefresh && onRefresh != null) {
      return await onRefresh!();
    }
    if (onRead != null) {
      return await onRead!();
    }
    return currentDataMap;
  }

  @override
  Future<Map<K, T>> refresh(() parameter) async {
    if (onRefresh != null) {
      return await onRefresh!();
    }
    onInvalidate();
    return currentDataMap;
  }

  @override
  void trigger(() parameter, {bool forceRefresh = false}) {
    get(parameter, forceRefresh: forceRefresh).ignore();
  }

  @override
  StatefulData<Map<K, T>> current(() parameter) {
    final data = currentDataMap;
    if (data.isEmpty) {
      return const DataInitial();
    }
    return DataLoaded(
      data,
      metadata: DataMetadata.now(source: DataSource.local),
    );
  }

  @override
  Map<K, T>? currentData(() parameter) {
    final data = currentDataMap;
    return data.isEmpty ? null : data;
  }

  @override
  void invalidate() => onInvalidate();
}

/// Convenience extension for parameterless [KeyedAccessor] instances where `P` is `()`.
extension ParameterlessKeyedAccessor<K extends Object, T>
    on KeyedAccessor<K, T, ()> {
  /// Reads or hydrates data for multiple [keys] without requiring an explicit `()` parameter.
  Future<Map<K, T>> getAll(
    Iterable<K> keys, {
    bool forceRefresh = false,
  }) => this.getAll(keys, const (), forceRefresh: forceRefresh);

  /// Forces fresh data fetches for multiple [keys] without requiring an explicit `()` parameter.
  Future<Map<K, T>> refreshKeys(Iterable<K> keys) =>
      this.refreshKeys(keys, const ());

  /// Triggers background fetches for multiple [keys] without requiring an explicit `()` parameter.
  void triggerKeys(Iterable<K> keys, {bool forceRefresh = false}) =>
      this.triggerKeys(keys, const (), forceRefresh: forceRefresh);

  /// Invalidates cache and state for multiple [keys] without requiring an explicit `()` parameter.
  void invalidateKeys(Iterable<K> keys) => this.invalidateKeys(keys);
}
