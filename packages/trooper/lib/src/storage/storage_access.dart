import 'package:meta/meta.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/storage/storage_backend.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';

/// L2 storage access shared by single and keyed troopers.
///
/// Routes every read, write and delete through [storageFor], which holds
/// them back while a purge started by [purgeStorage] is still running. A
/// `get` right after `invalidate()` therefore never sees purged data.
mixin StorageAccess {
  /// Configuration providing the [TrooperConfig.storage] backend.
  TrooperConfig get config;

  /// Telemetry hub receiving [PersistenceErrorEvent]s.
  TelemetryHub get telemetry;

  /// Namespace whose persisted entries this trooper owns.
  String get namespace;

  late final _PurgeAwareStorage? _storage = config.storage == null
      ? null
      : _PurgeAwareStorage(config.storage!);
  bool _reportedUnstableStorageKey = false;

  /// The L2 backend to use for [key], or `null` if no storage is configured
  /// or [key] has no stable storage key (see [QueryKey.hasStableStorageKey]).
  ///
  /// Reports the first unstable key as a [PersistenceErrorEvent].
  @protected
  StorageBackend? storageFor(QueryKey key) {
    final storage = _storage;
    if (storage == null || key.hasStableStorageKey) return storage;
    if (!_reportedUnstableStorageKey) {
      _reportedUnstableStorageKey = true;
      telemetry.emit(
        PersistenceErrorEvent(
          key,
          error: TrooperStorageException(
            'L2 storage skipped for ${key.describe()}: parameter or key has '
            'no stable toString(), so unequal values would share a storage key.',
          ),
          duration: Duration.zero,
        ),
      );
    }
    return null;
  }

  /// Deletes every persisted entry of [namespace], including entries written
  /// in earlier sessions, optionally narrowed by [where].
  ///
  /// Runs in the background; failures are reported as [PersistenceErrorEvent].
  @protected
  void purgeStorage({bool Function(String storageKey)? where}) {
    final storage = _storage;
    if (storage == null) return;
    final prefix = QueryKey.storagePrefix(namespace);
    final stopwatch = Stopwatch()..start();
    storage
        .purge((k) => k.startsWith(prefix) && (where == null || where(k)))
        .catchError((Object error, StackTrace stackTrace) {
          telemetry.emit(
            PersistenceErrorEvent(
              QueryKey(namespace, const ()),
              error: error,
              duration: stopwatch.elapsed,
              stackTrace: stackTrace,
            ),
          );
        });
  }
}

/// Delegates to a [StorageBackend] and holds operations back while a purge
/// is running.
final class _PurgeAwareStorage implements StorageBackend {
  _PurgeAwareStorage(this._backend);

  final StorageBackend _backend;
  Future<void>? _pendingPurge;

  /// Deletes all keys matching [where]. Later operations wait for it.
  Future<void> purge(bool Function(String key) where) {
    final previous = _pendingPurge;
    late final Future<void> current;
    current =
        (() async {
          if (previous != null) {
            try {
              await previous;
            } catch (_) {
              // Reported by the purge that failed.
            }
          }
          final keys = await _backend.getAllKeys();
          await Future.wait(keys.where(where).map(_backend.delete));
        })().whenComplete(() {
          if (identical(_pendingPurge, current)) _pendingPurge = null;
        });
    _pendingPurge = current;
    return current;
  }

  Future<R> _afterPurge<R>(Future<R> Function() operation) {
    final pending = _pendingPurge;
    if (pending == null) return operation();
    return pending.then((_) => operation(), onError: (_) => operation());
  }

  @override
  Future<String?> read(String key) => _afterPurge(() => _backend.read(key));

  @override
  Future<void> write(String key, String value) =>
      _afterPurge(() => _backend.write(key, value));

  @override
  Future<String?> delete(String key) => _afterPurge(() => _backend.delete(key));

  @override
  Future<void> clear() => _afterPurge(_backend.clear);

  @override
  Future<Set<String>> getAllKeys() => _afterPurge(_backend.getAllKeys);

  @override
  Future<bool> containsKey(String key) =>
      _afterPurge(() => _backend.containsKey(key));
}
