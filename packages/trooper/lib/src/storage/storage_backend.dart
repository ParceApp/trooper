import 'dart:async';

import 'package:trooper/src/key/query_key.dart';

/// An abstract interface for asynchronous key-value persistence backends (L2 storage).
///
/// Implemented by adapters for SharedPreferences, SQLite, Hive, local files, etc.
/// Allows queries to persist data across application restarts.
///
/// ### Example:
/// ```dart
/// class MySecureStorageBackend implements StorageBackend {
///   @override
///   Future<String?> read(String key) => ...;
///   ...
/// }
/// ```
abstract interface class StorageBackend {
  /// Reads the string value associated with [key], or `null` if not found.
  Future<String?> read(String key);

  /// Writes the string [value] for [key].
  Future<void> write(String key, String value);

  /// Deletes the entry associated with [key].
  Future<String?> delete(String key);

  /// Clears all stored entries from this storage backend.
  Future<void> clear();

  /// Returns all currently stored keys.
  ///
  /// Trooper uses this to purge every entry of a namespace (keys starting
  /// with [QueryKey.storagePrefix]) on `invalidate()` and `clearAll()`,
  /// including entries written in earlier sessions. It must return keys
  /// persisted by any session, not only by the current one.
  Future<Set<String>> getAllKeys();

  /// Returns `true` if an entry exists for [key].
  Future<bool> containsKey(String key);
}

/// An in-memory implementation of [StorageBackend].
///
/// Backed by a standard Dart [Map], ideal for unit testing, mocks, and
/// environments without disk access.
class InMemoryStorageBackend implements StorageBackend {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<String?> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async {
    _data.clear();
  }

  @override
  Future<Set<String>> getAllKeys() async => Set.unmodifiable(_data.keys);

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);

  /// Synchronous inspection of currently stored entries (useful in tests).
  int get count => _data.length;
}
