/// Callback signature for emitting states during source matching.
typedef Emit<State> = void Function(State state);

/// Represents the outcome of evaluating watched Trooper sources in `matchSources`.
enum MatchResult {
  /// Indicates that sources were successfully matched and a state transition was handled.
  handled,

  /// Indicates that the current source combination was not handled,
  /// delegating to `onAnyError` or `onAnyLoading`.
  unhandled;

  /// Whether this result indicates that sources were handled.
  bool get isHandled => this == MatchResult.handled;

  /// Whether this result indicates that sources were unhandled.
  bool get isUnhandled => this == MatchResult.unhandled;

  /// Creates a [MatchResult] from a boolean condition.
  factory MatchResult.fromBool(bool value) =>
      value ? MatchResult.handled : MatchResult.unhandled;
}
