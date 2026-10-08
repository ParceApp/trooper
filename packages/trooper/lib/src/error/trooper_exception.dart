import 'package:meta/meta.dart';

/// Base exception class for all errors originating within the Trooper framework.
@immutable
sealed class TrooperException implements Exception {
  /// Creates a [TrooperException] with a human-readable [message].
  const TrooperException(this.message, {this.error, this.stackTrace});

  /// A descriptive message explaining the error condition.
  final String message;

  /// The underlying error or exception that caused this failure, if any.
  final Object? error;

  /// The stack trace associated with [error] or this exception.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final typeName = switch (this) {
      TrooperCancelledException() => 'TrooperCancelledException',
      TrooperTimeoutException() => 'TrooperTimeoutException',
      TrooperStorageException() => 'TrooperStorageException',
    };
    final buffer = StringBuffer('$typeName: $message');
    if (error != null) {
      buffer.write(' (Error: $error)');
    }
    return buffer.toString();
  }
}

/// Thrown when an asynchronous operation is explicitly cancelled.
///
/// This occurs when a `TrooperCancelToken` is cancelled or when a newer
/// request supersedes a pending request under [QueryConflictPolicy.cancel].
final class TrooperCancelledException extends TrooperException {
  /// Creates a [TrooperCancelledException].
  const TrooperCancelledException({
    String message = 'The operation was cancelled.',
    super.error,
    super.stackTrace,
  }) : super(message);
}

/// Thrown when a fetch or network operation exceeds the configured timeout.
final class TrooperTimeoutException extends TrooperException {
  /// Creates a [TrooperTimeoutException] with the elapsed [timeout] duration.
  TrooperTimeoutException({
    required this.timeout,
    String? message,
    super.error,
    super.stackTrace,
  }) : super(
         message ??
             'The operation timed out after ${timeout.inMilliseconds} ms.',
       );

  /// The timeout threshold that was exceeded.
  final Duration timeout;
}

/// Thrown when an error occurs during reading from or writing to a `StorageBackend`.
final class TrooperStorageException extends TrooperException {
  /// Creates a [TrooperStorageException].
  const TrooperStorageException(super.message, {super.error, super.stackTrace});
}
