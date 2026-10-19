import 'package:meta/meta.dart';

/// Base exception class for all errors originating within the Trooper framework.
///
/// The set of subtypes is closed to user code but not exhaustive: new subtypes
/// can be added in minor releases. A `switch` over a [TrooperException] needs
/// a default case.
@immutable
abstract final class TrooperException implements Exception {
  /// Creates a [TrooperException] with a human-readable [message].
  const TrooperException(this.message, {this.error, this.stackTrace});

  /// A descriptive message explaining the error condition.
  final String message;

  /// The underlying error or exception that caused this failure, if any.
  final Object? error;

  /// The stack trace associated with [error] or this exception.
  final StackTrace? stackTrace;

  String get _typeName;

  @override
  String toString() {
    final buffer = StringBuffer('$_typeName: $message');
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

  @override
  String get _typeName => 'TrooperCancelledException';
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

  @override
  String get _typeName => 'TrooperTimeoutException';
}

/// Thrown when an error occurs during reading from or writing to a `StorageBackend`.
final class TrooperStorageException extends TrooperException {
  /// Creates a [TrooperStorageException].
  const TrooperStorageException(super.message, {super.error, super.stackTrace});

  @override
  String get _typeName => 'TrooperStorageException';
}

/// Thrown when a `TrooperCodec` fails to encode a value or to decode a
/// persisted string.
///
/// The original failure (for example a [FormatException]) is in [error].
/// Persistence errors caused by a codec are reported with this type in
/// `PersistenceErrorEvent.error`; failures of the `StorageBackend` itself are
/// reported as [TrooperStorageException].
final class TrooperCodecException extends TrooperException {
  /// Creates a [TrooperCodecException].
  const TrooperCodecException(super.message, {super.error, super.stackTrace});

  @override
  String get _typeName => 'TrooperCodecException';
}
