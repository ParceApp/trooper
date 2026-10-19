import 'dart:async';
import 'package:trooper/src/error/trooper_exception.dart';
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
  /// If [initialParameter] is provided and [eager] is `true`, an initial background fetch is triggered.
  /// If [initialParameter] is omitted or `null`, returns [stream] without triggering an eager fetch.
  StatefulStream<T> watch({P? initialParameter, bool eager = false});

  /// Reads the value for [parameter], returning immediately from cache if fresh,
  /// or fetching from the underlying source if stale or uncached.
  ///
  /// If [forceRefresh] is `true`, cache freshness is bypassed and a fresh fetch is performed.
  Future<T> get(P parameter, {bool forceRefresh = false});

  /// Forces a fresh get from the underlying source, bypassing cache freshness.
  Future<T> refresh(P parameter);

  /// Triggers a fetch in the background without awaiting the result.
  ///
  /// Ideal for reactive architectures where state updates and errors are observed via [watch].
  /// If [forceRefresh] is `true`, cache freshness is bypassed.
  void trigger(P parameter, {bool forceRefresh = false});

  /// Returns the current state synchronously.
  StatefulData<T> current();

  /// Returns the unwrapped data payload if the resource is currently [DataLoaded],
  /// or `null` otherwise.
  T? currentData();

  /// Marks cached data as stale across all parameters, removes storage, and resets state to [DataInitial].
  ///
  /// Removes every persisted L2 entry of the namespace, including entries
  /// written in earlier sessions. Requests still in flight are cancelled:
  /// their callers receive a [TrooperCancelledException].
  @override
  void invalidate();
}
