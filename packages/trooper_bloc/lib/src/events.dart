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
@immutable
abstract class TlocEvent {
  /// Const constructor for subclasses.
  const TlocEvent();
}
