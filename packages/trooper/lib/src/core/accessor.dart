import 'dart:async';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/types/parameter.dart';

/// Unified consumer interface for getting, watching, and observing resources.
///
/// An [Accessor] represents a reactive, side-effect free get facade over an underlying resource.
/// Both single queries and keyed queries scoped to a specific key
/// implement this interface, providing a consistent, read-only API across presentation and domain layers.
///
/// ### Example:
/// ```dart
/// final Accessor<UserProfile, ()> profileAccessor = userProfileQuery;
///
/// // Watch reactive state updates:
/// profileAccessor.watch(()).listen((state) {
///   print(state);
/// });
///
/// // Read the current or fresh value:
/// final profile = await profileAccessor.get(());
/// ```
abstract interface class Accessor<T, P extends Parameter>
    implements Invalidatable {
  /// The underlying [StatefulStream] emitting reactive [StatefulData] updates for this resource.
  StatefulStream<T> get stream;

  /// Watches reactive state updates of this resource.
  ///
  /// If [parameter] is provided and [eager] is `true`, a background fetch is automatically triggered.
  /// If [parameter] is omitted or `null`, returns [stream] without triggering an eager fetch.
  StatefulStream<T> watch([P? parameter, bool eager = true]);

  /// Reads the value for [parameter], returning immediately from cache if fresh,
  /// or fetching from the underlying source if stale or uncached.
  ///
  /// If [parameter] is omitted and `P` is `()`, defaults to `const ()`.
  /// If [forceRefresh] is `true`, cache freshness is bypassed and a fresh fetch is performed.
  Future<T> get([P? parameter, bool forceRefresh = false]);

  /// Forces a fresh get from the underlying source, bypassing cache freshness.
  ///
  /// If [parameter] is omitted and `P` is `()`, defaults to `const ()`.
  Future<T> refresh([P? parameter]);

  /// Triggers a fetch in the background without awaiting the result.
  ///
  /// Ideal for reactive architectures where state updates and errors are observed via [watch].
  /// If [parameter] is omitted and `P` is `()`, defaults to `const ()`.
  /// If [forceRefresh] is `true`, cache freshness is bypassed.
  void trigger([P? parameter, bool forceRefresh = false]);

  /// Returns the current state synchronously.
  StatefulData<T> current([P? parameter]);

  /// Returns the unwrapped data payload if the resource is currently [DataLoaded],
  /// or `null` otherwise.
  T? currentData([P? parameter]);

  /// Marks cached data as stale, removes storage, and resets state to [DataInitial].
  @override
  void invalidate();
}

/// Convenience extension for parameterless [Accessor] instances where `P` is `()`.
extension ParameterlessAccessor<T> on Accessor<T, ()> {
  /// Watches reactive state updates without requiring an explicit `()` parameter.
  StatefulStream<T> watch({bool eager = true}) => this.watch(const (), eager);

  /// Synchronously returns the current state without requiring an explicit `()` parameter.
  StatefulData<T> current() => this.current(const ());

  /// Synchronously returns current data payload without requiring an explicit `()` parameter.
  T? currentData() => this.currentData(const ());

  /// Reads the value without requiring an explicit `()` parameter.
  Future<T> get({bool forceRefresh = false}) =>
      this.get(const (), forceRefresh);

  /// Forces a fresh get without requiring an explicit `()` parameter.
  Future<T> refresh() => this.refresh(const ());

  /// Triggers a fetch in the background without requiring an explicit `()` parameter.
  void trigger({bool forceRefresh = false}) =>
      this.trigger(const (), forceRefresh);
}
