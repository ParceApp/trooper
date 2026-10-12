import 'package:trooper/src/error/trooper_exception.dart';

/// A cooperative cancellation token to abort ongoing asynchronous tasks.
///
/// Can be passed into fetchers, HTTP clients, or background tasks to react
/// to cancellation triggers.
///
/// ### Example:
/// ```dart
/// final token = TrooperCancelToken();
///
/// Future<User> fetchUser(TrooperCancelToken token) async {
///   final response = await httpClient.get('/user');
///   token.throwIfCancelled();
///   return User.fromJson(response);
/// }
///
/// // Cancel when no longer needed:
/// token.cancel(reason: 'User navigated away');
/// ```
class TrooperCancelToken {
  /// Creates a new uncancelled [TrooperCancelToken].
  TrooperCancelToken();

  bool _isCancelled = false;
  String? _reason;
  final List<void Function()> _listeners = [];

  /// Whether this token has been cancelled.
  bool get isCancelled => _isCancelled;

  /// The reason why this token was cancelled, or `null` if not set or the job is still running.
  String? get reason => _reason;

  /// Cancels this token with an optional [reason] and invokes registered listeners.
  ///
  /// Calling this method on an already cancelled token is a no-op.
  void cancel({String? reason}) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;

    final callbacks = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final callback in callbacks) {
      try {
        callback();
      } catch (_) {
        // Prevent one failing listener callback from aborting other callbacks
      }
    }
  }

  /// Throws a [TrooperCancelledException] if this token has been cancelled.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw TrooperCancelledException(
        message: _reason ?? 'Operation was cancelled',
      );
    }
  }

  /// Registers a [callback] to be invoked when this token is cancelled.
  ///
  /// Returns a function that unregisters the callback when invoked.
  /// If the token is already cancelled, the callback is invoked immediately.
  void Function() onCancel(void Function() callback) {
    if (_isCancelled) {
      try {
        callback();
      } catch (_) {}
      return () {};
    }
    _listeners.add(callback);
    return () => removeListener(callback);
  }

  /// Removes a previously registered [callback].
  ///
  /// Returns `true` if the callback was present and removed, `false` otherwise.
  bool removeListener(void Function() callback) => _listeners.remove(callback);
}
