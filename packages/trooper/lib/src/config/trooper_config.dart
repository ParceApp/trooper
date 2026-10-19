import 'package:trooper/src/config/query_conflict_policy.dart';
import 'package:trooper/src/config/retry_policy.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/storage/storage_backend.dart';

/// Configuration specifying caching, staleness, deduplication, conflict, timeout, and retry policies for a Trooper query.
final class TrooperConfig {
  /// Creates a [TrooperConfig] with customizable TTL, stale policy, conflict policy, deduplication, timeout, and optional storage.
  ///
  /// Defaults to standard Stale-While-Revalidate caching with 1 minute TTL, [QueryConflictPolicy.forward], and `deduplicate: true`.
  const TrooperConfig({
    this.timeToLive = const Duration(minutes: 1),
    this.stalePolicy = StalePolicy.keepStaleWhileRevalidate,
    this.conflictPolicy = QueryConflictPolicy.forward,
    this.deduplicate = true,
    this.storage,
    this.refreshAfterChangeDependencies = true,
    this.timeout,
    this.retryPolicy,
  });

  /// Ephemeral configuration without caching (TTL = 0).
  const TrooperConfig.noCache({
    this.conflictPolicy = QueryConflictPolicy.forward,
    this.deduplicate = true,
    this.refreshAfterChangeDependencies = true,
    this.timeout,
    this.retryPolicy,
  }) : timeToLive = Duration.zero,
       stalePolicy = StalePolicy.discardStaleOnRefresh,
       storage = null;

  /// How long cached data remains fresh before becoming stale.
  final Duration timeToLive;

  /// Strategy used when refreshing data.
  final StalePolicy stalePolicy;

  /// Policy controlling in-flight concurrent conflicts for the same query slot.
  ///
  /// Conflicts are queries with the same name and entity key but differing parameters, or when `forceRefresh: true` is requested.
  final QueryConflictPolicy conflictPolicy;

  /// Whether requests with identical parameters should be deduplicated (coalesced).
  ///
  /// When `true` (the default), subsequent callers requesting the same parameter while
  /// a request is in-flight share the ongoing [Future] instead of triggering redundant network calls.
  final bool deduplicate;

  /// Optional persistent storage backend for L2 persistence.
  ///
  /// Entries are stored under [QueryKey.storageKey], which is built from the
  /// `toString()` of the parameter (and entity key). Parameters without a
  /// stable `toString()` are not persisted (see [QueryKey.hasStableStorageKey]).
  final StorageBackend? storage;

  /// Whether `didChangeDependencies()` should trigger a refresh directly after invalidating.
  final bool refreshAfterChangeDependencies;

  /// Optional maximum duration allowed for in-flight operations before throwing a [TrooperTimeoutException].
  final Duration? timeout;

  /// Optional automated retry strategy executed when operations fail.
  final RetryPolicy? retryPolicy;

  /// Shorthand alias for [conflictPolicy].
  QueryConflictPolicy get queryConflictPolicy => conflictPolicy;

  /// Whether caching is enabled (TTL > zero).
  ///
  /// When `false` (e.g. [TrooperConfig.noCache]):
  /// - Queries ([QueryTrooper], [KeyedQueryTrooper]): strictly bypasses L1 cache on reads and writes; fetches directly from the data source.
  /// - Streams ([StreamTrooper], [KeyedStreamTrooper]): incoming frames update the stream controller directly without writing to L1 cache.
  /// - Local state ([LocalTrooper], [KeyedLocalTrooper]): in-memory state is maintained in memory as the primary source of truth.
  bool get hasCache => timeToLive > Duration.zero;

  /// Global default configuration used when no custom config is specified.
  static TrooperConfig defaultConfig = const TrooperConfig();

  /// Sets the default configuration for all troopers.
  /// This config can be overridden by individual troopers via their constructor.
  static void setDefaultConfig(TrooperConfig config) {
    defaultConfig = config;
  }

  /// Creates a copy of this config with updated properties.
  TrooperConfig copyWith({
    Duration? timeToLive,
    StalePolicy? stalePolicy,
    QueryConflictPolicy? conflictPolicy,
    bool? deduplicate,
    StorageBackend? storage,
    bool? refreshAfterChangeDependencies,
    Duration? timeout,
    RetryPolicy? retryPolicy,
  }) => TrooperConfig(
    timeToLive: timeToLive ?? this.timeToLive,
    stalePolicy: stalePolicy ?? this.stalePolicy,
    conflictPolicy: conflictPolicy ?? this.conflictPolicy,
    deduplicate: deduplicate ?? this.deduplicate,
    storage: storage ?? this.storage,
    refreshAfterChangeDependencies:
        refreshAfterChangeDependencies ?? this.refreshAfterChangeDependencies,
    timeout: timeout ?? this.timeout,
    retryPolicy: retryPolicy ?? this.retryPolicy,
  );
}
