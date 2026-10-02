import 'dart:async';
import 'package:trooper/src/conccurrency/cancel_token.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';

/// Orchestrates in-flight asynchronous operations per [QueryKey].
///
/// Provides:
/// - **Request Coalescing**: Concurrent requests for the same [QueryKey] share a single in-flight [Future].
/// - **Scoped Cancellation**: Enables cancelling requests by key, query namespace, or globally.
/// - **Lifecycle Integration**: Implements [LifecycleAware] to abort pending tasks on disposal.
///
/// ### Example:
/// ```dart
/// final queryQueue = TrooperQueryQueue();
///
/// const key = QueryKey.keyed('lecture', 42);
///
/// // Two concurrent calls execute the action only once:
/// final f1 = queryQueue.execute(key: key, action: (token) => fetchApi(42, token));
/// final f2 = queryQueue.execute(key: key, action: (token) => fetchApi(42, token));
/// assert(identical(f1, f2));
/// ```
class TrooperQueryQueue with LifecycleAware {
  final Map<QueryKey, _OngoingRequest<dynamic>> _ongoing = {};
  bool _isDisposed = false;

  /// Whether this queryQueue has been disposed.
  bool get isDisposed => _isDisposed;

  /// Returns the number of currently active in-flight requests.
  int get activeCount => _ongoing.length;

  /// Returns `true` if an operation is currently in-flight for [key].
  bool hasOngoing(QueryKey key) => _ongoing.containsKey(key);

  /// Executes an asynchronous [action] for the specified [key].
  ///
  /// - If a request for [QueryKey] is already in-flight and [forceRefresh] is `false`,
  ///   the existing in-flight [Future] is returned (Request Coalescing).
  /// - If [forceRefresh] is `true`,
  ///   the prior request's [TrooperCancelToken] is cancelled and a fresh request starts.
  Future<T> execute<T>({
    required QueryKey key,
    required Future<T> Function(TrooperCancelToken token) action,
    bool forceRefresh = false,
  }) {
    if (_isDisposed) {
      throw StateError(
        'Cannot execute request on a disposed RequestOrchestrator',
      );
    }

    // Return existing in-flight request if not forcing a new one
    final existing = _ongoing[key];
    if (existing != null && !forceRefresh) {
      return existing.future as Future<T>;
    }

    // If forcing new and strategy is replaceOngoing, cancel prior task
    if (existing != null && forceRefresh) {
      existing.cancelToken.cancel('Replaced by newer request for $key');
      _ongoing.remove(key);
    }

    final cancelToken = TrooperCancelToken();
    final completer = Completer<T>();
    final ongoing = _OngoingRequest<T>(completer.future, cancelToken);
    _ongoing[key] = ongoing;

    Future<void> runTask() async {
      try {
        final result = await action(cancelToken);
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        if (_ongoing[key]?.future == completer.future) {
          _ongoing.remove(key);
        }
      }
    }

    runTask().ignore();

    return completer.future;
  }

  /// Cancels any active in-flight request for the specified [key].
  void cancel(QueryKey key, [String? reason]) {
    if (_isDisposed) return;
    final ongoing = _ongoing.remove(key);
    ongoing?.cancelToken.cancel(reason ?? 'Cancelled for $key');
  }

  /// Cancels all active in-flight requests matching the query [familyName].
  void cancelNamespace(String familyName, [String? reason]) {
    if (_isDisposed) return;
    final keysToCancel = _ongoing.keys
        .where((key) => key.matchesName(familyName))
        .toList();

    for (final key in keysToCancel) {
      cancel(key, reason ?? 'Cancelled family $familyName');
    }
  }

  /// Cancels all active in-flight requests.
  void cancelAll([String? reason]) {
    if (_isDisposed) return;
    final entries = _ongoing.values.toList();
    _ongoing.clear();
    for (final ongoing in entries) {
      ongoing.cancelToken.cancel(reason ?? 'Cancelled all requests');
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    cancelAll('RequestOrchestrator disposed');
    _isDisposed = true;
  }
}

class _OngoingRequest<T> {
  const _OngoingRequest(this.future, this.cancelToken);
  final Future<T> future;
  final TrooperCancelToken cancelToken;
}
