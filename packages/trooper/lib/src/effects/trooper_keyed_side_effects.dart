import 'dart:async';
import 'package:trooper/types/parameter.dart';

/// Side-effect callbacks for keyed KeyedTrooperQuery collections.
///
/// Each callback receives the specific entity key along with the payload and parameters.
///
/// ### Example:
/// ```dart
/// final lectureQuery = KeyedTrooperQuery<String, Lecture, ()>(
///   namespace: 'lecture',
///   fetch: (id, _) => api.getLecture(id),
///   sideEffects: KeyedTrooperSideEffects(
///     onData: (id, lecture, _) => print('Lecture $id loaded: ${lecture.title}'),
///     onError: (id, error, _, __) => print('Failed to load lecture $id: $error'),
///   ),
/// );
/// ```
class KeyedTrooperSideEffects<K, T, P extends Parameter> {
  /// Creates a [KeyedTrooperSideEffects] bundle.
  const KeyedTrooperSideEffects({
    this.onData,
    this.onError,
    this.onRequestStarted,
    this.transformRequestResult,
    this.onSocketDataReceived,
    this.onCacheExpired,
    this.notifyBeforeCacheExpired = const <Duration>[],
    this.beforeCacheExpired,
  });

  /// Invoked when fresh data is loaded, set, or revalidated for the entity key.
  final FutureOr<void> Function(K key, T data, P param)? onData;

  /// Invoked when an asynchronous operation for the entity key fails with an error.
  final FutureOr<void> Function(
    K key,
    Object error,
    StackTrace stackTrace,
    P param,
  )?
  onError;

  /// Invoked when an asynchronous request for the entity key begins.
  final FutureOr<void> Function(K key, P param)? onRequestStarted;

  /// Invoked after a request for the entity key has been successfully completed or a stream deliver data.
  /// Can be used to perform transformation directly after the data is received.
  /// This hook can be provided if you want to transform the result with a different value.
  final FutureOr<T> Function(K key, T data, P param)? transformRequestResult;

  /// Invoked when cached data for the entity key has expired and needs to be refreshed.
  /// Can be used to monitor cache expiration and take appropriate actions.
  final void Function(K key, T? data)? onCacheExpired;

  /// List of Durations that defines when the method [beforeCacheExpired] should be called before the cache expired.
  final List<Duration> notifyBeforeCacheExpired;

  /// Invoked before cached data for the entity key expires, providing the cached value and the time remaining until expiration.
  /// Can be used to perform actions or notifications before the cache is considered stale.
  /// The [timeBefore] is controller by the [notifyBeforeCacheExpired] list, which defines the specific durations before expiration when this callback should be triggered.
  final void Function(K key, T? data, Duration timeBefore)? beforeCacheExpired;

  /// Invoked after data for the entity key is received and processed from a socket.
  /// An optional return value can be provided if you want to override or transform the result of the request with a different value.
  final FutureOr<T?> Function(K key, T data)? onSocketDataReceived;
}
