import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/state/data_metadata.dart';

/// Sealed hierarchy of telemetry and diagnostic events emitted by the Trooper engine.
sealed class TrooperEvent {
  TrooperEvent({DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  /// The exact moment this event occurred.
  final DateTime timestamp;
}

/// Emitted when an asynchronous request or fetch operation begins.
final class RequestStartedEvent extends TrooperEvent {
  RequestStartedEvent(this.key, {super.timestamp});
  final QueryKey key;

  @override
  String toString() => 'RequestStartedEvent(${key.describe()})';
}

/// Emitted when a query is served directly from the in-memory cache.
final class CacheHitEvent extends TrooperEvent {
  /// Creates a [CacheHitEvent].
  CacheHitEvent(
    this.key, {
    required this.isFresh,
    this.metadata,
    super.timestamp,
  });

  /// The cache query key that was hit.
  final QueryKey key;

  /// Whether the cached entry was fresh at the time of access.
  final bool isFresh;

  /// Optional metadata describing the origin and expiration of the cached entry.
  final DataMetadata? metadata;

  @override
  String toString() =>
      'CacheHitEvent(${key.describe()}, fresh: $isFresh, source: ${metadata?.source})';
}

/// Emitted when stale cached data is served and a background revalidation is started (SWR).
final class SWRTriggeredEvent extends TrooperEvent {
  SWRTriggeredEvent(this.key, {super.timestamp});
  final QueryKey key;

  @override
  String toString() => 'SWRTriggeredEvent(${key.describe()})';
}

/// Emitted when a request completes successfully.
final class RequestCompletedEvent extends TrooperEvent {
  RequestCompletedEvent(
    this.key, {
    required this.duration,
    required this.source,
    super.timestamp,
  });

  final QueryKey key;
  final Duration duration;
  final DataSource source;

  @override
  String toString() =>
      'RequestCompletedEvent(${key.describe()}, source: $source, duration: ${duration.inMilliseconds}ms)';
}

/// Emitted when a request fails with an error.
final class RequestErrorEvent extends TrooperEvent {
  RequestErrorEvent(
    this.key, {
    required this.error,
    required this.duration,
    this.stackTrace,
    super.timestamp,
  });

  final QueryKey key;
  final Object error;
  final Duration duration;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'RequestErrorEvent(${key.describe()}, error: $error, duration: ${duration.inMilliseconds}ms)';
}

/// Emitted when an error occurs during a persistence operation, such as saving or loading data from local storage.
final class PersistenceErrorEvent extends TrooperEvent {
  PersistenceErrorEvent(
    this.key, {
    required this.error,
    required this.duration,
    this.stackTrace,
    super.timestamp,
  });

  final QueryKey key;
  final Object error;
  final Duration duration;
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'PersistenceErrorEvent(${key.describe()}, error: $error, duration: ${duration.inMilliseconds}ms)';
}

/// Emitted when a cache entry or query namespace is invalidated.
final class CacheInvalidatedEvent extends TrooperEvent {
  CacheInvalidatedEvent(this.key, {super.timestamp});
  final QueryKey key;

  @override
  String toString() => 'CacheInvalidatedEvent(${key.describe()})';
}

/// Emitted when data is manually set or updated in a Trooper.
final class DataSetEvent extends TrooperEvent {
  DataSetEvent(this.key, {this.source = DataSource.local, super.timestamp});

  final QueryKey key;
  final DataSource source;

  @override
  String toString() => 'DataSetEvent(${key.describe()}, source: $source)';
}
