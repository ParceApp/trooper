import 'dart:async';

import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/storage/storage_envelope.dart';

/// An abstract interface for asynchronous key-value persistence backends (L2 storage).
///
/// Implemented by adapters for SharedPreferences, SQLite, Hive, local files, etc.
/// Allows queries to persist data across application restarts.
///
/// ### Contract
/// - **Errors:** every method may throw or complete with an error. Trooper
///   catches each failure, reports it as a `PersistenceErrorEvent` (with a
///   [TrooperStorageException] where Trooper itself detects the problem) and
///   continues without L2; a failing backend never fails a read.
/// - **Concurrency:** calls can overlap, also for the same key (for example a
///   background write and a later read). Trooper only waits for its own
///   purges: after `invalidate()` or `clearAll()`, later calls start once all
///   deletes of the purge have completed.
/// - **Shared backends:** the backend may also hold data of the app. Trooper
///   only reads, writes and deletes keys that start with
///   [QueryKey.storagePrefix] of one of its namespaces, and it never clears the
///   backend as a whole.
/// - **Keys and values** are non-empty strings; [read] returns exactly the
///   last value passed to [write] for that key, or `null`.
///
/// New capabilities will be added as separate optional interfaces, so
/// implementing this interface stays non-breaking across minor releases.
///
/// ### Plain text
/// Trooper writes values as plain-text JSON (a [StorageEnvelope] around the codec
/// output) and keys as readable [QueryKey.storageKey]s. Nothing is encrypted. For
/// sensitive data, implement this interface over an encrypted store or wrap an
/// existing backend in a decorator that encrypts values in [write] and decrypts
/// them in [read]; keep keys unencrypted, as [getAllKeys] is matched by prefix.
/// See "Persistence & Sensitive Data" in the README for a complete example.
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

  /// Writes the string [value] for [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Deletes the entry associated with [key]. Deleting a missing key is not
  /// an error.
  Future<void> delete(String key);

  /// Returns all currently stored keys.
  ///
  /// Trooper uses this to purge every entry of a namespace (keys starting
  /// with [QueryKey.storagePrefix]) on `invalidate()` and `clearAll()`,
  /// including entries written in earlier sessions. It must return keys
  /// persisted by any session, not only by the current one. Keys that do not
  /// belong to Trooper are ignored.
  Future<Set<String>> getAllKeys();
}

/// An in-memory implementation of [StorageBackend].
///
/// Backed by a standard Dart [Map], ideal for unit testing, mocks, and
/// environments without disk access.
final class InMemoryStorageBackend implements StorageBackend {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<Set<String>> getAllKeys() async => Set.unmodifiable(_data.keys);

  /// Synchronous inspection of currently stored entries (useful in tests).
  int get count => _data.length;
}
