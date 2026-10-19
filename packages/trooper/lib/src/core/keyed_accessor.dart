import 'dart:async';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/core/accessor.dart';
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
  void triggerKeys(Iterable<K> keys, P parameter, {bool forceRefresh = false});

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
