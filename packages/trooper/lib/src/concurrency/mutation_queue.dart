import 'dart:async';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';

/// A sequential FIFO execution queue for mutations and write operations.
///
/// Ensures that write operations execute strictly in the order they were submitted,
/// preventing race conditions and out-of-order state overwrites.
///
/// ### Example:
/// ```dart
/// final queue = MutationQueue();
///
/// // These execute strictly sequentially:
/// queue.add(() => updateProfile(name: 'Alice'));
/// queue.add(() => updateProfile(name: 'Bob'));
/// ```
class TrooperMutationQueue with LifecycleAware {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;
  bool _isDisposed = false;
  final Set<Completer<dynamic>> _pendingCompleters = {};

  /// Whether this queue has been disposed.
  bool get isDisposed => _isDisposed;

  /// The number of tasks currently executing or waiting in the queue.
  int get pendingCount => _pending;

  /// Returns `true` if a mutation is actively running or queued.
  bool get isProcessing => _pending > 0;

  /// Enqueues an asynchronous [task] and returns a [Future] completing with its result.
  ///
  /// Tasks execute sequentially. If a prior task throws an error, subsequent tasks
  /// in the queue still execute normally.
  Future<T> add<T>(Future<T> Function() task) {
    if (_isDisposed) {
      throw StateError('Cannot enqueue task to a disposed MutationQueue');
    }

    _pending++;
    final completer = Completer<T>();
    _pendingCompleters.add(completer);

    _tail = _tail.catchError((_) {}).then((_) async {
      final wasPending = _pendingCompleters.remove(completer);

      if (_isDisposed || completer.isCompleted) {
        if (wasPending && !completer.isCompleted) {
          _pending--;
          completer.completeError(
            const TrooperCancelledException(
              message: 'MutationQueue was disposed',
            ),
          );
        }
        return;
      }

      try {
        final result = await task();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _pending--;
      }
    });

    return completer.future;
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    final toCancel = _pendingCompleters.toList();
    _pendingCompleters.clear();
    for (final completer in toCancel) {
      if (!completer.isCompleted) {
        _pending--;
        completer.completeError(
          const TrooperCancelledException(
            message: 'MutationQueue was disposed',
          ),
        );
      }
    }
  }
}
