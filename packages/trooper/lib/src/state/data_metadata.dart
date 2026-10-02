import 'package:meta/meta.dart';

/// Describes the origin source from which data was retrieved.
enum DataSource {
  /// The data was freshly fetched from a remote network endpoint (REST, GraphQL, etc.).
  network,

  /// The data was served from the L1 in-memory RAM cache.
  cache,

  /// The data was loaded from persistent L2 storage (Disk, SQLite, SharedPreferences).
  storage,

  /// The data was set locally in-memory (e.g. via `localTrooper.set()`).
  local,
}

/// Metadata associated with a loaded or refreshing data state.
///
/// Contains temporal and provenance information, such as when the data was
/// fetched, when its cache entry expires, and where it originated from.
///
/// ### Example:
/// ```dart
/// if (state case DataLoaded(:final data, :final metadata)) {
///   if (metadata?.isStale ?? false) {
///     print('Showing stale data fetched ${metadata?.age?.inMinutes} min ago');
///   }
/// }
/// ```
@immutable
class DataMetadata {
  /// Creates metadata for a loaded data state.
  const DataMetadata({
    required this.fetchedAt,
    required this.source,
    this.expiresAt,
  });

  /// Creates metadata timestamped at the current time.
  DataMetadata.now({required this.source, Duration? ttl})
    : fetchedAt = DateTime.now(),
      expiresAt = ttl != null ? DateTime.now().add(ttl) : null;

  /// The timestamp when this data was fetched or created.
  final DateTime fetchedAt;

  /// The timestamp when this data should be considered stale and revalidated.
  ///
  /// If `null`, this data never automatically expires based on time.
  final DateTime? expiresAt;

  /// The provenance source from which this data was retrieved.
  final DataSource source;

  /// Whether the data has passed its [expiresAt] timestamp.
  bool get isStale => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// The duration since the data was fetched.
  Duration get age => DateTime.now().difference(fetchedAt);

  /// The remaining time until this data becomes stale, or `null` if it never expires.
  Duration? get timeToLive {
    final expires = expiresAt;
    if (expires == null) return null;
    final remaining = expires.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Creates a copy of this metadata with optional field overrides.
  DataMetadata copyWith({
    DateTime? fetchedAt,
    DateTime? expiresAt,
    DataSource? source,
  }) => DataMetadata(
    fetchedAt: fetchedAt ?? this.fetchedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    source: source ?? this.source,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataMetadata &&
          runtimeType == other.runtimeType &&
          fetchedAt == other.fetchedAt &&
          expiresAt == other.expiresAt &&
          source == other.source;

  @override
  int get hashCode => Object.hash(fetchedAt, expiresAt, source);

  @override
  String toString() =>
      'DataMetadata(source: $source, fetchedAt: $fetchedAt, expiresAt: $expiresAt, isStale: $isStale)';
}
