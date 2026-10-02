import 'package:trooper/src/state/data_metadata.dart';

/// An in-memory cache envelope holding a cached [data] item, its creation timestamp,
/// and its lifecycle metadata (TTL, staleness, source).
///
/// ### Example:
/// ```dart
/// final entry = CacheEntry<User>(
///   user,
///   timeToLive: const Duration(minutes: 5),
/// );
///
/// if (entry.isStale) {
///   print('Cache is stale, triggering background revalidation');
/// }
/// ```
class CacheEntry<T> {
  /// Creates a [CacheEntry] with the given [data] and optional [timeToLive].
  CacheEntry(
    this.data, {
    this.timeToLive,
    this.source = DataSource.cache,
    DateTime? createdAt,
    this.isManuallyInvalidated = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       expiresAt = timeToLive != null
           ? (createdAt ?? DateTime.now()).add(timeToLive)
           : null;

  /// The cached data payload.
  final T data;

  /// The timestamp when this entry was created or fetched.
  final DateTime createdAt;

  /// The duration for which this entry is considered fresh.
  /// If `null`, the entry never expires based on time.
  final Duration? timeToLive;

  /// The origin of this entry (e.g. [DataSource.network], [DataSource.cache]).
  final DataSource source;

  /// Whether this entry was explicitly invalidated before its TTL expired.
  final bool isManuallyInvalidated;

  /// The exact timestamp when this entry expires, or `null` if it has no TTL.
  final DateTime? expiresAt;

  /// The elapsed duration since this entry was created.
  Duration get age => DateTime.now().difference(createdAt);

  /// Whether the entry's TTL has expired.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether this entry is considered stale (either TTL expired or manually invalidated).
  bool get isStale => isManuallyInvalidated || isExpired;

  /// Whether this entry is currently fresh and valid.
  bool get isFresh => !isStale;

  /// Generates a [DataMetadata] descriptor capturing the current state of this entry.
  DataMetadata get metadata => DataMetadata(
    fetchedAt: createdAt,
    source: source,
    expiresAt: isManuallyInvalidated
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : expiresAt,
  );

  /// Returns a copy of this entry marked as manually invalidated.
  CacheEntry<T> markStale() => copyWith(isManuallyInvalidated: true);

  /// Creates a copy with optionally updated fields.
  CacheEntry<T> copyWith({
    T? data,
    Duration? timeToLive,
    DataSource? source,
    DateTime? createdAt,
    bool? isManuallyInvalidated,
  }) => CacheEntry<T>(
    data ?? this.data,
    timeToLive: timeToLive ?? this.timeToLive,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    isManuallyInvalidated: isManuallyInvalidated ?? this.isManuallyInvalidated,
  );

  @override
  String toString() =>
      'CacheEntry(data: $data, fresh: $isFresh, age: ${age.inSeconds}s)';
}
