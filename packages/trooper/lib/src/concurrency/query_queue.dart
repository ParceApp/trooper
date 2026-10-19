import 'dart:async';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/config/query_conflict_policy.dart';
import 'package:trooper/src/config/retry_policy.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';

/// Orchestrates in-flight asynchronous operations per [QueryKey].
///
/// Provides:
/// - **Configurable Conflict Handling**: Supports [QueryConflictPolicy] (`cancel`, `forward`, `parallel`).
/// - **Request Deduplication**: Requests with matching parameters share a single in-flight [Future] by default (`deduplicate: true`).
/// - **Safe Supercession (Forwarding)**: Old requests can be cancelled while awaiting callers are seamlessly forwarded to the new result.
/// - **Scoped Cancellation**: Enables cancelling requests by key, query namespace, or globally.
/// - **Lifecycle Integration**: Implements [LifecycleAware] to abort pending tasks on disposal.
///
/// ### Example:
/// ```dart
/// final queryQueue = TrooperQueryQueue();
///
/// const key = QueryKey('lecture', (id: 42));
///
/// // Two concurrent calls execute the action only once via deduplication:
/// final f1 = queryQueue.execute(key: key, action: (token) => fetchApi(42, token));
/// final f2 = queryQueue.execute(key: key, action: (token) => fetchApi(42, token));
/// assert(identical(f1, f2));
/// ```
final class TrooperQueryQueue with LifecycleAware {
  final List<_OngoingRequest<dynamic>> _ongoingList = [];
  bool _isDisposed = false;

  /// Whether this query queue has been disposed.
  bool get isDisposed => _isDisposed;

  /// Returns the number of currently active in-flight requests.
  int get activeCount => _ongoingList.length;

  /// Returns `true` if an operation is currently in-flight for [key].
  bool hasOngoing(QueryKey key) => _findOngoing(key) != null;

  /// Executes an asynchronous [action] for the specified [key] governed by [conflictPolicy] and [deduplicate].
  ///
  /// - When [deduplicate] is `true` (the default) and a request matching [key]'s query name, entity key,
  ///   and parameters is in-flight without [forceRefresh], the existing future is reused without
  ///   starting a new network request.
  /// - Under [QueryConflictPolicy.cancel], an active in-flight request for the same slot is cancelled
  ///   and its caller receives a [TrooperCancelledException].
  /// - Under [QueryConflictPolicy.forward], the active request's cancel token is cancelled, but
  ///   the waiting caller's future is chained to the new request without error.
  /// - Under [QueryConflictPolicy.parallel], both requests run concurrently.
  Future<T> execute<T>({
    required QueryKey key,
    required Future<T> Function(TrooperCancelToken token) action,
    QueryConflictPolicy conflictPolicy = QueryConflictPolicy.forward,
    bool deduplicate = true,
    bool forceRefresh = false,
    Duration? timeout,
    RetryPolicy? retryPolicy,
  }) {
    if (_isDisposed) {
      throw StateError(
        'Cannot execute request on a disposed TrooperQueryQueue',
      );
    }

    final existing = _findOngoing(key);
    final isSameParam =
        existing != null && existing.key.matchesParameter(key.parameter);

    // 1. Deduplication: if enabled, parameters match, and not forcing fresh request
    if (existing != null && isSameParam && !forceRefresh && deduplicate) {
      return existing.future as Future<T>;
    }

    // Preparing
    final cancelToken = TrooperCancelToken();
    final completer = Completer<T>();
    final ongoing = _OngoingRequest<T>(
      key: key,
      future: completer.future,
      completer: completer,
      cancelToken: cancelToken,
    );

    // 2. Handle active in-flight request based on conflictPolicy
    if (existing != null) {
      switch (conflictPolicy) {
        case QueryConflictPolicy.cancel:
          existing.cancelToken.cancel(
            reason: 'Replaced by newer request for ${key.describe()}',
          );
          if (!existing.completer.isCompleted) {
            existing.completer.completeError(
              TrooperCancelledException(
                message:
                    'The query request was superseded by a newer request for ${key.describe()}.',
              ),
            );
          }
          _ongoingList.remove(existing);

        case QueryConflictPolicy.forward:
          // From now on only the new request completes the prior caller;
          // whatever the superseded action yields (late result, cancellation,
          // retry abort) is discarded.
          existing.isForwarded = true;
          existing.cancelToken.cancel(
            reason: 'Superseded by newer request for ${key.describe()}',
          );
          _linkCompleter(existing.completer, completer.future);
          _ongoingList.remove(existing);

        case QueryConflictPolicy.parallel:
          // Keep existing running in parallel; do not cancel or remove.
          break;
      }
    }

    _ongoingList.add(ongoing);

    bool mayComplete() => !ongoing.isForwarded && !completer.isCompleted;

    Future<void> runTask() async {
      try {
        var attempt = 0;
        while (true) {
          attempt++;
          try {
            Future<T> actionFuture = action(cancelToken);
            if (timeout != null) {
              actionFuture = actionFuture.timeout(
                timeout,
                onTimeout: () => throw TrooperTimeoutException(
                  timeout: timeout,
                  message:
                      'Operation on ${key.describe()} timed out after ${timeout.inMilliseconds} ms.',
                ),
              );
            }
            final result = await actionFuture;
            if (mayComplete()) {
              completer.complete(result);
            }
            break;
          } catch (error, stackTrace) {
            final isCancelled =
                cancelToken.isCancelled || error is TrooperCancelledException;
            final shouldRetry =
                !isCancelled &&
                retryPolicy != null &&
                retryPolicy.shouldRetry(error, attempt);

            if (shouldRetry) {
              final delay = retryPolicy.delayForAttempt(attempt);
              if (delay > Duration.zero) {
                await Future<void>.delayed(delay);
              }
              if (cancelToken.isCancelled) {
                if (mayComplete()) {
                  completer.completeError(
                    TrooperCancelledException(
                      message: cancelToken.reason ?? 'Operation cancelled',
                    ),
                    stackTrace,
                  );
                }
                break;
              }
              continue;
            }

            if (mayComplete()) {
              completer.completeError(error, stackTrace);
            }
            break;
          }
        }
      } finally {
        _ongoingList.remove(ongoing);
      }
    }

    runTask().ignore();

    return completer.future;
  }

  /// Cancels any active in-flight request matching the exact [key].
  void cancel(QueryKey key, {String? reason}) {
    if (_isDisposed) return;
    final matching = _ongoingList
        .where(
          (r) => r.key.matches(
            name: key.name,
            parameter: key.parameter,
            entityKey: key.key,
          ),
        )
        .toList();

    for (final ongoing in matching) {
      _ongoingList.remove(ongoing);
      ongoing.cancelToken.cancel(
        reason: reason ?? 'Cancelled for ${key.describe()}',
      );
      if (!ongoing.completer.isCompleted) {
        ongoing.completer.completeError(
          TrooperCancelledException(
            message: reason ?? 'Cancelled for ${key.describe()}',
          ),
        );
      }
    }
  }

  /// Cancels all active in-flight requests matching query [namespace].
  void cancelNamespace(String namespace, {String? reason}) {
    if (_isDisposed) return;
    final matching = _ongoingList
        .where((r) => r.key.matchesName(namespace))
        .toList();

    for (final ongoing in matching) {
      _ongoingList.remove(ongoing);
      ongoing.cancelToken.cancel(
        reason: reason ?? 'Cancelled query namespace $namespace',
      );
      if (!ongoing.completer.isCompleted) {
        ongoing.completer.completeError(
          TrooperCancelledException(
            message: reason ?? 'Cancelled query namespace $namespace',
          ),
        );
      }
    }
  }

  /// Cancels all active in-flight requests satisfying [predicate].
  void cancelWhere(bool Function(QueryKey key) predicate, {String? reason}) {
    if (_isDisposed) return;
    final matching = _ongoingList.where((r) => predicate(r.key)).toList();
    for (final ongoing in matching) {
      _ongoingList.remove(ongoing);
      ongoing.cancelToken.cancel(reason: reason ?? 'Cancelled by query queue');
      if (!ongoing.completer.isCompleted) {
        ongoing.completer.completeError(
          TrooperCancelledException(
            message: reason ?? 'Cancelled by query queue',
          ),
        );
      }
    }
  }

  /// Cancels all active in-flight requests.
  void cancelAll({String? reason}) {
    if (_isDisposed) return;
    final entries = List<_OngoingRequest<dynamic>>.of(_ongoingList);
    _ongoingList.clear();

    for (final ongoing in entries) {
      ongoing.cancelToken.cancel(reason: reason ?? 'Cancelled all requests');
      if (!ongoing.completer.isCompleted) {
        ongoing.completer.completeError(
          TrooperCancelledException(
            message: reason ?? 'Cancelled all requests',
          ),
        );
      }
    }
  }

  _OngoingRequest<dynamic>? _findOngoing(QueryKey key) {
    for (var i = _ongoingList.length - 1; i >= 0; i--) {
      final req = _ongoingList[i];
      if (req.key.matchesNameAndKey(name: key.name, entityKey: key.key)) {
        return req;
      }
    }
    return null;
  }

  void _linkCompleter<R>(Completer<dynamic> oldCompleter, Future<R> newFuture) {
    newFuture.then(
      (value) {
        if (!oldCompleter.isCompleted) {
          oldCompleter.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!oldCompleter.isCompleted) {
          oldCompleter.completeError(error, stackTrace);
        }
      },
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    cancelAll(reason: 'TrooperQueryQueue disposed');
    _isDisposed = true;
  }
}

class _OngoingRequest<T> {
  _OngoingRequest({
    required this.key,
    required this.future,
    required this.completer,
    required this.cancelToken,
  });

  final QueryKey key;
  final Future<T> future;
  final Completer<T> completer;
  final TrooperCancelToken cancelToken;

  /// Set once a newer request took over this caller under
  /// [QueryConflictPolicy.forward].
  bool isForwarded = false;
}
