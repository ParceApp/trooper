import 'package:meta/meta.dart';

/// Base class for all domain events processed by a [Tloc].
///
/// Subclasses should define their events using sealed class hierarchies:
/// ```dart
/// sealed class UserEvent extends TlocEvent {
///   const UserEvent();
/// }
///
/// final class LoadUserEvent extends UserEvent {
///   const LoadUserEvent();
/// }
/// ```
///
/// ### Extending
/// Extend this class; do not `implements` it. Implementing it is not
/// supported, and new members can be added in minor releases.
@immutable
abstract class TlocEvent {
  /// Const constructor for subclasses.
  const TlocEvent();
}

/// Internal framework event dispatched when a [Tloc] emits a state from watched sources
/// or via direct state emissions.
///
/// Not exported. It still reaches `BlocObserver.onEvent` and `onTransition`,
/// where it shows up by its `toString()`.
final class TlocSourceUpdateEvent extends TlocEvent {
  /// Creates a [TlocSourceUpdateEvent] wrapping [state].
  const TlocSourceUpdateEvent(this.state);

  /// The state being emitted.
  final Object? state;

  @override
  String toString() => 'TlocSourceUpdateEvent($state)';
}
