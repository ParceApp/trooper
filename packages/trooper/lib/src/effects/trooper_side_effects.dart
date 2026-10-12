import 'dart:async';
import 'package:trooper/types/parameter.dart';

/// Side-effect callbacks for single Trooper queries and local state.
///
/// Encapsulates lifecycle hooks for reacting to data arrivals, errors,
/// and request lifecycles without coupling side effects to presentation UI.
///
/// ### Example:
/// ```dart
/// final userQuery = QueryTrooper<User, ({int id})>(
///   namespace: 'user',
///   fetch: (param) => api.getUser(param.id),
///   sideEffects: TrooperSideEffects(
///     onData: (user, param) => analytics.logUserLoaded(user.id),
///     onError: (error, stack, param) => crashlytics.report(error, stack),
///   ),
/// );
/// ```
class TrooperSideEffects<T, P extends Parameter> {
  /// Creates a [TrooperSideEffects] bundle.
  const TrooperSideEffects({
    this.onData,
    this.onError,
    this.onRequestStarted,
    this.transformRequestResult,
    this.onSocketDataReceived,
    this.onCacheExpired,
    this.notifyBeforeCacheExpired = const <Duration>[],
    this.beforeCacheExpired,
  }) : assert(
         beforeCacheExpired == null || notifyBeforeCacheExpired.length > 0,
         'If beforeCacheExpired is provided, notifyBeforeCacheExpired must contain at least one Duration.',
       );

  /// Invoked when fresh data is loaded, set, or revalidated.
  final FutureOr<void> Function(T data, P param)? onData;

  /// Invoked when an asynchronous operation fails with an error.
  final FutureOr<void> Function(Object error, StackTrace stackTrace, P param)?
  onError;

  /// Invoked when an asynchronous request or fetch begins.
  final FutureOr<void> Function(P param)? onRequestStarted;

  /// Invoked after a request has been successfully completed or a stream deliver data.
  /// Can be used to perform transformation directly after the data is received.
  /// This hook can be provided if you want to transform the result with a different value.
  final FutureOr<T> Function(T data, P param)? transformRequestResult;

  /// Invoked when cached data has expired and needs to be refreshed.
  /// Can be used to monitor cache expiration and take appropriate actions.
  final void Function(T? expiredValue)? onCacheExpired;

  /// List of Durations that defines when the method [beforeCacheExpired] should be called before the cache expired.
  final List<Duration> notifyBeforeCacheExpired;

  /// Invoked before cached data expires, providing the cached value and the time remaining until expiration.
  /// Can be used to perform actions or notifications before the cache is considered stale.
  /// The [timeBefore] is controller by the [notifyBeforeCacheExpired] list, which defines the specific durations before expiration when this callback should be triggered.
  final void Function(T? data, Duration timeBefore)? beforeCacheExpired;

  /// Invoked after data is received and processed from a socket.
  /// An optional return value can be provided if you want to override or transform the result of the request with a different value.
  final FutureOr<T?> Function(T data)? onSocketDataReceived;
}
