import 'dart:async';

/// Side-effect callbacks for TrooperMutation commands.
///
/// ### Example:
/// ```dart
/// final createTodo = TrooperMutation<Todo, ({String title})>(
///   name: 'createTodo',
///   action: (param) => api.createTodo(param.title),
///   sideEffects: TrooperMutationSideEffects(
///     onSuccess: (todo, param) => showToast('Created ${todo.title}'),
///     onError: (error, stack, param) => showToast('Failed: $error'),
///   ),
/// );
/// ```
class TrooperMutationSideEffects<T, P extends Record> {
  /// Creates a [TrooperMutationSideEffects] bundle.
  const TrooperMutationSideEffects({
    this.onSuccess,
    this.onError,
    this.onStarted,
  });

  /// Invoked when the mutation completes successfully with the result value.
  final FutureOr<void> Function(T result, P param)? onSuccess;

  /// Invoked when the mutation fails with an error.
  final FutureOr<void> Function(Object error, StackTrace stackTrace, P param)?
  onError;

  /// Invoked when the mutation starts executing.
  final FutureOr<void> Function(P param)? onStarted;
}
