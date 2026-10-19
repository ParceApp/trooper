import 'dart:async';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/storage/cache_entry.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';

/// An in-memory L1 cache store managing cached entries partitioned by [QueryKey].
///
/// Features:
/// - Per-entry TTL and staleness tracking via [CacheEntry].
/// - Targetable invalidation by key, namespace, or predicate.
/// - Invalidation notification stream via [invalidationStream].
/// - Full integration with [LifecycleAware] and [Invalidatable].
///
/// ### Memory bounds
/// By default the store is unbounded: entries stay until they are removed,
/// cleared, or evicted after expiry. Expired entries are evicted on access, or
/// periodically if [evictionInterval] is set. For apps with a growing key space
/// (chat rooms, detail pages by ID), set [maxEntries] to cap the store; the least
/// recently used entries are then dropped first. Eviction only frees memory: it
/// does not notify [invalidationStream], and the next read fetches again.
///
/// Keyed troopers also keep each key's latest state in their
/// [KeyedStatefulStream] until `removeKey`, `clearAll` or `dispose`, independent
/// of this store. With an unbounded key space, create `KeyedQueryTrooper` and
/// `KeyedStreamTrooper` with `releaseUnwatchedKeys: true` (drops a key's
/// in-memory state once nobody watches it) or remove keys you no longer need.
///
/// ### Example:
/// ```dart
/// final cache = CacheStore();
///
/// const key = QueryKey.keyed('lecture', parameter: (), key: 'math-101');
/// cache.put(key, lecture, timeToLive: const Duration(minutes: 10));
///
/// // Later, when fresh:
/// final cached = cache.get<Lecture>(key);
///
/// // Invalidate all lectures:
/// cache.invalidateNamespace('lecture');
/// ```
final class CacheStore with LifecycleAware implements Invalidatable {
  /// Creates an in-memory [CacheStore].
  ///
  /// If [evictionInterval] is provided, an internal timer periodically runs
  /// [removeExpired] to actively prune expired cache entries.
  ///
  /// If [maxEntries] is provided, the store holds at most that many entries and
  /// evicts the least recently used one when a new entry is added.
  CacheStore({this.evictionInterval, this.maxEntries})
    : assert(maxEntries == null || maxEntries > 0, 'maxEntries must be > 0') {
    _invalidationController = StreamController<QueryKey>.broadcast();
    if (evictionInterval != null) {
      _evictionTimer = Timer.periodic(
        evictionInterval!,
        (_) => removeExpired(),
      );
    }
  }

  /// Optional interval at which expired cache entries are automatically evicted.
  final Duration? evictionInterval;
  Timer? _evictionTimer;

  /// Optional maximum number of entries; `null` (the default) means unbounded.
  ///
  /// Reads via [getEntry] and [get] and writes via [put] and [putEntry] mark an
  /// entry as recently used.
  final int? maxEntries;

  final Map<QueryKey, CacheEntry<dynamic>> _entries = {};
  late final StreamController<QueryKey> _invalidationController;
  bool _isDisposed = false;

  /// Whether this cache store has been disposed.
  bool get isDisposed => _isDisposed;

  /// Stream notifying listeners whenever a [QueryKey] is invalidated.
  Stream<QueryKey> get invalidationStream => _invalidationController.stream;

  /// Returns the current number of cached entries.
  int get size => _entries.length;

  /// Returns an unmodifiable snapshot of all currently tracked [QueryKey]s.
  Set<QueryKey> get keys => Set.unmodifiable(_entries.keys);

  /// Stores a [data] value under [key] with an optional [timeToLive].
  ///
  /// The [source] records where the data originated from (defaults to [DataSource.cache]).
  /// Repositories or fetchers can provide their provenance (e.g. [DataSource.network]
  /// or [DataSource.storage]) to preserve origin tracking in [DataMetadata].
  void put<T>(
    QueryKey key,
    T data, {
    Duration? timeToLive,
    DataSource source = DataSource.cache,
  }) {
    if (_isDisposed) return;

    _store(key, CacheEntry<T>(data, timeToLive: timeToLive, source: source));
  }

  /// Stores an existing [CacheEntry] under [key].
  void putEntry<T>(QueryKey key, CacheEntry<T> entry) {
    if (_isDisposed) return;
    _store(key, entry);
  }

  void _store(QueryKey key, CacheEntry<dynamic> entry) {
    // Re-inserting moves the key to the most recently used end.
    _entries.remove(key);
    _entries[key] = entry;
    final limit = maxEntries;
    if (limit == null) return;
    while (_entries.length > limit) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Retrieves the [CacheEntry] for [key], or `null` if not present or type mismatch.
  ///
  /// If [allowExpired] is `false` and the entry is expired, the entry is evicted
  /// from the cache and `null` is returned.
  CacheEntry<T>? getEntry<T>(QueryKey key, {bool allowExpired = true}) {
    if (_isDisposed) return null;
    final entry = _entries[key];
    if (entry is CacheEntry<T>) {
      if (!allowExpired && entry.isExpired) {
        _entries.remove(key);
        return null;
      }
      if (maxEntries != null) {
        _entries
          ..remove(key)
          ..[key] = entry;
      }
      return entry;
    }
    return null;
  }

  /// Convenience shortcut to retrieve the raw cached data payload for [key].
  ///
  /// If [allowExpired] is `false` and the entry is expired, the entry is evicted
  /// from the cache and `null` is returned.
  T? get<T>(QueryKey key, {bool allowExpired = true}) =>
      getEntry<T>(key, allowExpired: allowExpired)?.data;

  /// Returns `true` if an entry exists for [key].
  bool containsKey(QueryKey key) => _entries.containsKey(key);

  /// Returns `true` if [key] has an entry that is currently fresh (not stale).
  bool isFresh(QueryKey key) => getEntry<dynamic>(key)?.isFresh ?? false;

  /// Returns `true` if [key] is absent or its entry is considered stale.
  bool isStale(QueryKey key) => !isFresh(key);

  /// Marks the entry for [key] as manually stale and notifies listeners.
  void invalidateKey(QueryKey key) {
    if (_isDisposed) return;
    final entry = _entries[key];
    if (entry != null) {
      _entries[key] = entry.markStale();
      _invalidationController.add(key);
    }
  }

  /// Marks all entries belonging to query [name] as stale.
  void invalidateNamespace(String name) {
    if (_isDisposed) return;
    for (final key in _entries.keys.toList()) {
      if (key.matchesName(name)) {
        invalidateKey(key);
      }
    }
  }

  /// Marks all entries satisfying [predicate] as stale.
  void invalidateWhere(bool Function(QueryKey key) predicate) {
    if (_isDisposed) return;
    for (final key in _entries.keys.toList()) {
      if (predicate(key)) {
        invalidateKey(key);
      }
    }
  }

  /// Invalidates all currently stored entries. Implements [Invalidatable].
  @override
  void invalidate() {
    if (_isDisposed) return;
    _entries.keys.toList().forEach(invalidateKey);
  }

  /// Removes [key] completely from the cache.
  void remove(QueryKey key) {
    if (_isDisposed) return;
    _entries.remove(key);
  }

  /// Removes all entries satisfying [predicate].
  void removeWhere(bool Function(QueryKey key) predicate) {
    if (_isDisposed) return;
    _entries.removeWhere((key, _) => predicate(key));
  }

  /// Removes all entries whose [QueryKey.name] equals [namespace].
  void removeName(String namespace) {
    removeWhere((key) => key.matchesName(namespace));
  }

  /// Removes all entries whose TTL has expired.
  void removeExpired() {
    if (_isDisposed) return;
    _entries.removeWhere((_, entry) => entry.isExpired);
  }

  /// Clears all entries from the store.
  void clear() {
    if (_isDisposed) return;
    _entries.clear();
  }

  ///
  @override
  void pause() {
    _evictionTimer?.cancel();
    _evictionTimer = null;
    removeExpired();
  }

  @override
  void resume() {
    if (!_isDisposed && evictionInterval != null && _evictionTimer == null) {
      _evictionTimer = Timer.periodic(
        evictionInterval!,
        (_) => removeExpired(),
      );
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _evictionTimer?.cancel();
    _evictionTimer = null;
    _entries.clear();
    await _invalidationController.close();
  }
}
