import 'dart:async';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_trooper.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/storage/cache_entry.dart';
import 'package:trooper/src/storage/storage_envelope.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// A [KeyedTrooper] managing in-memory mutable local application or UI state per key.
///
/// Designed for keyed collections of client-side state, drafts, input forms, or dynamic filters.
/// Provides:
/// - In-memory state tracking per entity [K].
/// - Optional asynchronous persistence and hydration via [codec] and [StorageBackend].
/// - Fine-grained reactive streams per key as well as aggregate collection watching.
///
/// ### Example:
/// ```dart
/// final drafts = KeyedLocalTrooper<String, String, ()>(
///   namespace: 'chat_drafts',
///   initialValue: '',
///   codec: TrooperCodec.string,
/// );
///
/// // Access single chat draft via subscript operator:
/// final chatDraft = drafts['room-101'];
/// print(chatDraft.currentData(())); // ''
///
/// // Mutate:
/// drafts.setKey('room-101', 'Hello world', ());
/// drafts.updateKey('room-101', (text) => '$text!', ());
/// drafts.resetKey('room-101', ());
///
/// // Watch all drafts:
/// drafts.watchAll().listen((map) {
///   print('Active drafts: ${map.length}');
/// });
/// ```
class KeyedLocalTrooper<K extends Object, T, P extends Parameter>
    extends KeyedTrooper<K, T, P> {
  /// Creates a [KeyedLocalTrooper] with a static [initialValue] for all keys.
  KeyedLocalTrooper({
    required super.namespace,
    required T initialValue,
    super.config,
    super.cache,
    super.sideEffects,
    this.codec,
    super.queryQueue,
    super.telemetry,
    super.stream,
  }) : initialValueFactory = ((_) => initialValue);

  /// Creates a [KeyedLocalTrooper] using a dynamic [initialValueFactory] per key.
  KeyedLocalTrooper.builder({
    required super.namespace,
    required this.initialValueFactory,
    super.config,
    super.cache,
    super.sideEffects,
    this.codec,
    super.queryQueue,
    super.telemetry,
    super.stream,
  });

  /// Function generating baseline initial value for any given key.
  final T Function(K key) initialValueFactory;

  /// Optional codec for persistent L2 storage synchronization.
  final TrooperCodec<T>? codec;

  final Set<K> _hydratedKeys = {};

  /// Whether [key] has been hydrated from L2 storage.
  bool isHydratedKey(K key) => _hydratedKeys.contains(key);

  /// Returns the baseline initial value for [key].
  T initialValueOf(K key) => initialValueFactory(key);

  /// Convenient subscript operator to acquire a bound [Accessor] for [key].
  @override
  Accessor<T, P> operator [](K key) =>
      _KeyedLocalBoundAccessor<K, T, P>(this, key);

  /// Updates the local state for [key] to [value] and returns the updated value.
  ///
  /// Emits [DataLoaded] on [stream], updates L1 cache, and asynchronously persists
  /// to L2 storage if configured.
  T setKey(K key, T value, P parameter) {
    final qKey = buildQueryKey(key, parameter);

    cache.put(
      qKey,
      value,
      timeToLive: config.timeToLive,
      source: DataSource.local,
    );

    final entry = cache.getEntry<T>(qKey);
    stream.emitData(key, value, metadata: entry?.metadata);

    if (telemetry.hasListeners) {
      telemetry.emit(DataSetEvent(qKey, source: DataSource.local));
    }

    runSideEffect(() => sideEffects?.onData?.call(key, value, parameter));

    final storage = config.storage;
    final currentCodec = codec;
    if (storage != null && currentCodec != null) {
      try {
        final serialized = currentCodec.encode(value);
        final now = DateTime.now();
        final envelope = StorageEnvelope(
          payload: serialized,
          createdAt: now,
          expiresAt: config.hasCache ? now.add(config.timeToLive) : null,
          timeToLiveMillis: config.hasCache
              ? config.timeToLive.inMilliseconds
              : null,
        );
        storage.write(qKey.storageKey, envelope.encode()).catchError(
          (Object error, StackTrace stackTrace) {
            telemetry.emit(
              PersistenceErrorEvent(
                qKey,
                error: error,
                duration: Duration.zero,
                stackTrace: stackTrace,
              ),
            );
          },
        );
      } catch (error, stackTrace) {
        telemetry.emit(
          PersistenceErrorEvent(
            qKey,
            error: error,
            duration: Duration.zero,
            stackTrace: stackTrace,
          ),
        );
        throw TrooperStorageException(
          'Failed to serialize state for ${qKey.name}',
          error: error,
        );
      }
    }
    return value;
  }

  /// Sets [value] for [key] in memory and awaits asynchronous persistence to [StorageBackend],
  /// throwing a [TrooperStorageException] if writing to persistent storage fails.
  Future<T> setKeyAsync(K key, T value, P parameter) async {
    setKey(key, value, parameter);
    final storage = config.storage;
    final currentCodec = codec;
    if (storage != null && currentCodec != null) {
      final qKey = buildQueryKey(key, parameter);
      try {
        final serialized = currentCodec.encode(value);
        final now = DateTime.now();
        final envelope = StorageEnvelope(
          payload: serialized,
          createdAt: now,
          expiresAt: config.hasCache ? now.add(config.timeToLive) : null,
          timeToLiveMillis: config.hasCache
              ? config.timeToLive.inMilliseconds
              : null,
        );
        await storage.write(qKey.storageKey, envelope.encode());
      } catch (error, stackTrace) {
        telemetry.emit(
          PersistenceErrorEvent(
            qKey,
            error: error,
            duration: Duration.zero,
            stackTrace: stackTrace,
          ),
        );
        throw TrooperStorageException(
          'Failed to persist state for ${qKey.name} to storage backend',
          error: error,
        );
      }
    }
    return value;
  }

  /// Updates the state for [key] by applying [transform] to its current value
  /// and returns the updated value.
  T updateKey(K key, T Function(T current) transform, P parameter) {
    final current = currentKeyData(key) ?? initialValueFactory(key);
    final updated = transform(current);
    setKey(key, updated, parameter);
    return updated;
  }

  /// Resets the state for [key] back to its initial value, deletes persistent storage,
  /// and returns the initial value.
  T resetKey(K key, P parameter) {
    final initial = initialValueFactory(key);
    setKey(key, initial, parameter);

    final storage = config.storage;
    if (storage != null) {
      final qKey = buildQueryKey(key, parameter);
      storage.delete(qKey.storageKey).ignore();
    }
    return initial;
  }

  /// Resets state for [key] back to its initial value and awaits deletion from persistent storage,
  /// throwing a [TrooperStorageException] if storage deletion fails.
  Future<T> resetKeyAsync(K key, P parameter) async {
    resetKey(key, parameter);
    final storage = config.storage;
    if (storage != null) {
      final qKey = buildQueryKey(key, parameter);
      try {
        await storage.delete(qKey.storageKey);
      } catch (error, stackTrace) {
        telemetry.emit(
          PersistenceErrorEvent(
            qKey,
            error: error,
            duration: Duration.zero,
            stackTrace: stackTrace,
          ),
        );
        throw TrooperStorageException(
          'Failed to delete persisted state for ${qKey.name} from storage backend',
          error: error,
        );
      }
    }
    return initialValueFactory(key);
  }

  /// Resets all currently tracked keys back to their initial values.
  void resetAll() {
    for (final key in activeKeys) {
      final param = lastParamOf(key);
      if (param != null) {
        resetKey(key, param);
      }
    }
  }

  /// Sets multiple key-value pairs in memory and fires asynchronous persistence for each.
  Map<K, T> setAll(Map<K, T> entries, P parameter) {
    entries.forEach((key, value) {
      setKey(key, value, parameter);
    });
    return entries;
  }

  /// Sets multiple key-value pairs in memory and awaits asynchronous persistence for all of them.
  ///
  /// Throws a [TrooperStorageException] if writing to persistent storage fails for any entry.
  Future<Map<K, T>> setAllAsync(Map<K, T> entries, P parameter) async {
    await Future.wait(
      entries.entries.map((e) => setKeyAsync(e.key, e.value, parameter)),
    );
    return entries;
  }

  /// Updates multiple keys using their corresponding [transforms] functions.
  Map<K, T> updateAll(
    Map<K, T Function(T current)> transforms,
    P parameter,
  ) {
    final results = <K, T>{};
    transforms.forEach((key, transform) {
      results[key] = updateKey(key, transform, parameter);
    });
    return results;
  }

  /// Resets the specified [keys] back to their initial values, deletes persistent storage,
  /// and returns a map of their initial values.
  Map<K, T> resetKeys(Iterable<K> keys, P parameter) {
    final results = <K, T>{};
    for (final key in keys) {
      results[key] = resetKey(key, parameter);
    }
    return results;
  }

  /// Resets the specified [keys] back to their initial values and awaits deletion from persistent storage.
  ///
  /// Throws a [TrooperStorageException] if storage deletion fails.
  Future<Map<K, T>> resetKeysAsync(Iterable<K> keys, P parameter) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => resetKeyAsync(k, parameter)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => getKey(k, parameter, forceRefresh: forceRefresh)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  /// Reads the value for [key], returning cached data if fresh, hydrating from L2
  /// storage if configured, or falling back to [initialValueFactory].
  Future<T> getKey(K key, P parameter, {bool forceRefresh = false}) async {
    final qKey = buildQueryKey(key, parameter);

    // 1. Check L1 Memory Cache (local state is always kept in memory)
    if (!forceRefresh) {
      final entry = cache.getEntry<T>(qKey);
      if (entry != null && entry.isFresh) {
        if (telemetry.hasListeners) {
          telemetry.emit(
            CacheHitEvent(qKey, isFresh: true, metadata: entry.metadata),
          );
        }
        stream.emitData(key, entry.data, metadata: entry.metadata);
        return entry.data;
      }
    }

    // 2. Hydrate from L2 Storage if configured and not yet hydrated
    if (!_hydratedKeys.contains(key) &&
        config.storage != null &&
        codec != null) {
      final storage = config.storage!;
      final currentCodec = codec!;

      try {
        final serialized = await storage.read(qKey.storageKey);
        if (serialized != null) {
          final envelope = StorageEnvelope.tryDecode(serialized);
          if (envelope == null) {
            storage.delete(qKey.storageKey).ignore();
          } else if (envelope.isExpired) {
            storage.delete(qKey.storageKey).ignore();
          } else {
            final decoded = currentCodec.decode(envelope.payload);
            final entry = CacheEntry<T>(
              decoded,
              createdAt: envelope.createdAt,
              expiresAt: envelope.expiresAt,
              timeToLive: envelope.timeToLive,
              source: DataSource.storage,
            );
            cache.putEntry(qKey, entry);
            if (telemetry.hasListeners) {
              telemetry.emit(
                CacheHitEvent(qKey, isFresh: true, metadata: entry.metadata),
              );
            }
            stream.emitData(key, decoded, metadata: entry.metadata);
            runSideEffect(
              () => sideEffects?.onData?.call(key, decoded, parameter),
            );
            _hydratedKeys.add(key);
            return decoded;
          }
        }
      } catch (_) {
        storage.delete(qKey.storageKey).ignore();
      }

      _hydratedKeys.add(key);
    }

    // 3. Fallback to stream value or initial baseline
    if (!stream.containsKey(key)) {
      final initial = initialValueFactory(key);
      cache.put(
        qKey,
        initial,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
      final entry = cache.getEntry<T>(qKey);
      stream.emitData(key, initial, metadata: entry?.metadata);
      return initial;
    }

    return currentKeyData(key) ?? initialValueFactory(key);
  }

  /// Refreshes the value for [key] by re-reading from storage.
  Future<T> refreshKey(K key, P parameter) =>
      getKey(key, parameter, forceRefresh: true);

  /// Triggers reading or hydrating data for [key] without awaiting the result.
  void triggerKey(K key, P parameter, {bool forceRefresh = false}) {
    getKey(key, parameter, forceRefresh: forceRefresh).ignore();
  }

  /// Watches state updates for a single [key].
  StatefulStream<T> watchKey(K key, P parameter, {bool eager = true}) {
    if (!stream.containsKey(key)) {
      final initial = initialValueFactory(key);
      final qKey = buildQueryKey(key, parameter);
      cache.put(
        qKey,
        initial,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
      final entry = cache.getEntry<T>(qKey);
      stream.emitData(key, initial, metadata: entry?.metadata);
    }

    if (eager &&
        !_hydratedKeys.contains(key) &&
        config.storage != null &&
        codec != null) {
      getKey(key, parameter).ignore();
    }

    return stream.streamOf(key);
  }

  /// Returns the current state for [key] synchronously.
  StatefulData<T> currentKeyState(K key) {
    if (stream.containsKey(key)) {
      return stream.stateOf(key);
    }
    return DataLoaded(
      initialValueFactory(key),
      metadata: DataMetadata.now(source: DataSource.local),
    );
  }

  @override
  T? currentKeyData(K key) => stream.containsKey(key)
      ? stream.stateOf(key).dataOrNull
      : initialValueFactory(key);

  @override
  void invalidateKey(K key, [P? parameter]) {
    super.invalidateKey(key, parameter);
    _hydratedKeys.remove(key);
  }

  @override
  void invalidate() {
    super.invalidate();
    _hydratedKeys.clear();
  }

  @override
  Future<void> removeKey(K key, [P? parameter]) async {
    _hydratedKeys.remove(key);
    await super.removeKey(key, parameter);
  }

  @override
  Future<void> clearAll() async {
    _hydratedKeys.clear();
    await super.clearAll();
  }

  /// Purges cache and resets all active keys back to baseline via [initialValueFactory].
  @override
  FutureOr<void> didChangeDependencies() {
    invalidate();
    if (config.refreshAfterChangeDependencies) {
      resetAll();
    }
  }

  @override
  Future<void> dispose() async {
    _hydratedKeys.clear();
    await super.dispose();
  }
}

class _KeyedLocalBoundAccessor<K extends Object, T, P extends Parameter>
    implements Accessor<T, P> {
  const _KeyedLocalBoundAccessor(this._parent, this._key);
  final KeyedLocalTrooper<K, T, P> _parent;
  final K _key;

  @override
  StatefulStream<T> watch(P parameter, {bool eager = true}) =>
      _parent.watchKey(_key, parameter, eager: eager);

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) =>
      _parent.getKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  void trigger(P parameter, {bool forceRefresh = false}) =>
      _parent.triggerKey(_key, parameter, forceRefresh: forceRefresh);

  @override
  Future<T> refresh(P parameter) => _parent.refreshKey(_key, parameter);

  @override
  StatefulData<T> current(P parameter) => _parent.currentKeyState(_key);

  @override
  T? currentData(P parameter) => _parent.currentKeyData(_key);

  @override
  void invalidate() => _parent.invalidateKey(_key);
}

/// Convenience extension for parameterless [KeyedLocalTrooper] instances where `P` is `()`.
extension ParameterlessKeyedLocalTrooper<K extends Object, T>
    on KeyedLocalTrooper<K, T, ()> {
  /// Reads or hydrates data for [key] without requiring an explicit `()` parameter.
  Future<T> getKey(K key, {bool forceRefresh = false}) =>
      this.getKey(key, const (), forceRefresh: forceRefresh);

  /// Sets data for [key] without requiring an explicit `()` parameter.
  T setKey(K key, T value) => this.setKey(key, value, const ());

  /// Sets data for [key] and awaits persistent storage without requiring an explicit `()` parameter.
  Future<T> setKeyAsync(K key, T value) => this.setKeyAsync(key, value, const ());

  /// Updates state for [key] without requiring an explicit `()` parameter.
  T updateKey(K key, T Function(T current) transform) =>
      this.updateKey(key, transform, const ());

  /// Resets state for [key] without requiring an explicit `()` parameter.
  T resetKey(K key) => this.resetKey(key, const ());

  /// Resets state for [key] and awaits deletion from persistent storage without requiring an explicit `()` parameter.
  Future<T> resetKeyAsync(K key) => this.resetKeyAsync(key, const ());

  /// Refreshes state for [key] without requiring an explicit `()` parameter.
  Future<T> refreshKey(K key) => this.refreshKey(key, const ());

  /// Triggers reading or hydrating data for [key] without requiring an explicit `()` parameter.
  void triggerKey(K key, {bool forceRefresh = false}) =>
      this.triggerKey(key, const (), forceRefresh: forceRefresh);

  /// Sets multiple key-value pairs without requiring an explicit `()` parameter.
  Map<K, T> setAll(Map<K, T> entries) => this.setAll(entries, const ());

  /// Sets multiple key-value pairs and awaits persistence without requiring an explicit `()` parameter.
  Future<Map<K, T>> setAllAsync(Map<K, T> entries) =>
      this.setAllAsync(entries, const ());

  /// Updates multiple keys without requiring an explicit `()` parameter.
  Map<K, T> updateAll(Map<K, T Function(T current)> transforms) =>
      this.updateAll(transforms, const ());

  /// Resets multiple keys without requiring an explicit `()` parameter.
  Map<K, T> resetKeys(Iterable<K> keys) => this.resetKeys(keys, const ());

  /// Resets multiple keys and awaits storage deletion without requiring an explicit `()` parameter.
  Future<Map<K, T>> resetKeysAsync(Iterable<K> keys) =>
      this.resetKeysAsync(keys, const ());

  /// Reads or hydrates multiple keys without requiring an explicit `()` parameter.
  Future<Map<K, T>> getAll(
    Iterable<K> keys, {
    bool forceRefresh = false,
  }) => this.getAll(keys, const (), forceRefresh: forceRefresh);

  /// Watches state updates for a single [key] without requiring an explicit `()` parameter.
  StatefulStream<T> watchKey(K key, {bool eager = true}) =>
      this.watchKey(key, const (), eager: eager);
}
