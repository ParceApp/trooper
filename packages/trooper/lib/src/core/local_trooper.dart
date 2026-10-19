import 'dart:async';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/trooper.dart';
import 'package:trooper/src/error/trooper_exception.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';
import 'package:trooper/src/storage/cache_entry.dart';
import 'package:trooper/src/storage/storage_envelope.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// A [Trooper] managing in-memory mutable local application or UI state.
///
/// Unlike query troopers that fetch from external networks, a [LocalTrooper] holds
/// an authoritative in-memory state that can be synchronously updated via [set],
/// [update], and [reset], with optional persistent backing via [TrooperConfig.storage]
/// and [codec].
///
/// Implements [Accessor], so widgets can consume and watch it identically to remote queries.
///
/// ### Example:
/// ```dart
/// final themeTrooper = LocalTrooper<String, ()>(
///   namespace: 'app_theme',
///   initialValue: 'system',
///   codec: TrooperCodec.string,
/// );
///
/// // Read or watch:
/// print(themeTrooper.currentData(())); // 'system'
///
/// // Update:
/// themeTrooper.set('dark', ());
///
/// // Functional update:
/// themeTrooper.update((theme) => theme == 'dark' ? 'light' : 'dark', ());
///
/// // Reset back to initial value:
/// themeTrooper.reset(());
/// ```
class LocalTrooper<T, P extends Parameter> extends Trooper<T, P> {
  /// Creates a [LocalTrooper] with the specified [initialValue].
  LocalTrooper({
    required super.namespace,
    required this.initialValue,
    this.codec,
    super.config,
    super.sideEffects,
    super.cache,
    super.queryQueue,
    super.telemetry,
    StatefulStreamController<T>? streamController,
  }) : super(
         streamController:
             streamController ??
             StatefulStreamController<T>(
               initialState: DataLoaded(
                 initialValue,
                 metadata: DataMetadata.now(source: DataSource.local),
               ),
             ),
       ) {
    if (const () is P) {
      final key = buildQueryKey(const () as P);
      cache.put(
        key,
        initialValue,
        timeToLive: config.timeToLive,
        source: DataSource.local,
      );
    }
  }

  /// The default baseline value restored when [reset] is called.
  final T initialValue;

  /// Optional codec used for persistent L2 storage synchronization.
  final TrooperCodec<T>? codec;

  bool _isHydrated = false;

  /// Whether this local trooper has completed hydration from L2 storage.
  bool get isHydrated => _isHydrated;

  /// Sets the in-memory value directly, updates the cache, emits on the stream,
  /// and returns the newly set [value].
  @override
  T set(T value, P parameter) {
    recordParam(parameter);
    final key = buildQueryKey(parameter);

    cache.put(
      key,
      value,
      timeToLive: config.timeToLive,
      source: DataSource.local,
    );

    final entry = cache.getEntry<T>(key);
    streamController.emitData(value, metadata: entry?.metadata);

    if (telemetry.hasListeners) {
      telemetry.emit(
        RequestCompletedEvent(
          key,
          duration: Duration.zero,
          source: DataSource.local,
        ),
      );
    }

    runSideEffect(() => sideEffects?.onData?.call(value, parameter));

    // Persist to L2 storage asynchronously if configured
    final storage = storageFor(key);
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
        writeStored(storage, key, envelope.encode());
      } catch (error, stackTrace) {
        reportPersistenceError(key, error, stackTrace);
        throw TrooperStorageException(
          'Failed to serialize state for ${key.name}',
          error: error,
        );
      }
    }

    return value;
  }

  /// Sets [value] in memory and awaits asynchronous persistence to [StorageBackend],
  /// throwing a [TrooperStorageException] if writing to persistent storage fails.
  Future<T> setAsync(T value, P parameter) async {
    set(value, parameter);
    final key = buildQueryKey(parameter);
    final storage = storageFor(key);
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
        await storage.write(key.storageKey, envelope.encode());
      } catch (error, stackTrace) {
        reportPersistenceError(key, error, stackTrace);
        throw TrooperStorageException(
          'Failed to persist state for ${key.name} to storage backend',
          error: error,
        );
      }
    }
    return value;
  }

  /// Updates the local state by applying [transform] to the current value
  /// and returns the updated value.
  T update(T Function(T current) transform, P parameter) {
    final current = currentData() ?? initialValue;
    final updated = transform(current);
    set(updated, parameter);
    return updated;
  }

  /// Resets the state back to [initialValue], deletes persisted storage,
  /// and returns [initialValue].
  T reset(P parameter) {
    recordParam(parameter);
    final key = buildQueryKey(parameter);

    set(initialValue, parameter);

    final storage = storageFor(key);
    if (storage != null) {
      deleteStored(storage, key);
    }

    return initialValue;
  }

  /// Resets state back to [initialValue] and awaits deletion from persistent storage,
  /// throwing a [TrooperStorageException] if storage deletion fails.
  Future<T> resetAsync(P parameter) async {
    reset(parameter);
    final key = buildQueryKey(parameter);
    final storage = storageFor(key);
    if (storage != null) {
      try {
        await storage.delete(key.storageKey);
      } catch (error, stackTrace) {
        reportPersistenceError(key, error, stackTrace);
        throw TrooperStorageException(
          'Failed to delete persisted state for ${key.name} from storage backend',
          error: error,
        );
      }
    }
    return initialValue;
  }

  /// Reads the value for [parameter], returning immediately from cache if fresh,
  /// or fetching from the underlying source if stale or uncached.
  ///
  /// [forceRefresh] is ignored for local troopers, as they are authoritative in-memory state.
  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) async {
    recordParam(parameter);
    final key = buildQueryKey(parameter);

    // Hydrate from L2 storage if configured and not yet hydrated
    if (!_isHydrated && storageFor(key) != null && codec != null) {
      final storage = storageFor(key)!;
      final currentCodec = codec!;

      try {
        final serialized = await storage.read(key.storageKey);
        if (serialized != null) {
          final envelope = StorageEnvelope.tryDecode(serialized);
          if (envelope == null) {
            discardStored(storage, key);
          } else if (envelope.isExpired) {
            deleteStored(storage, key);
          } else {
            final decoded = currentCodec.decode(envelope.payload);
            final entry = CacheEntry<T>(
              decoded,
              createdAt: envelope.createdAt,
              expiresAt: envelope.expiresAt,
              timeToLive: envelope.timeToLive,
              source: DataSource.storage,
            );
            cache.putEntry(key, entry);
            streamController.emitData(decoded, metadata: entry.metadata);
            runSideEffect(() => sideEffects?.onData?.call(decoded, parameter));
            _isHydrated = true;
            return decoded;
          }
        }
      } catch (error, stackTrace) {
        discardStored(storage, key, error, stackTrace);
      }

      _isHydrated = true;
    }

    return currentData() ?? initialValue;
  }

  @override
  StatefulStream<T> watch({P? initialParameter, bool eager = false}) {
    if (eager &&
        initialParameter != null &&
        !_isHydrated &&
        config.storage != null &&
        codec != null) {
      get(initialParameter).ignore();
    }
    return streamController.stream;
  }

  /// Hydrates the local state from persistent L2 storage if configured and not yet hydrated.
  @override
  Future<void> initialize() async {
    if (!_isHydrated && config.storage != null && codec != null) {
      final param = lastParam;
      if (param != null) {
        await get(param);
      }
    }
  }

  /// No-op for local in-memory troopers.
  @override
  FutureOr<void> recover() {}

  /// Invalidates cache, clears persistent storage, and resets state to [DataInitial].
  @override
  void invalidate() {
    _isHydrated = false;
    super.invalidate();
  }

  /// Invalidates cache and optionally resets the state back to [initialValue].
  @override
  FutureOr<void> didChangeDependencies() {
    invalidate();
    if (config.refreshAfterChangeDependencies) {
      final param = lastParam;
      if (param != null) {
        reset(param);
      }
    }
  }
}

/// Convenience extension for parameterless [LocalTrooper] instances where `P` is `()`.
extension ParameterlessLocalTrooper<T> on LocalTrooper<T, ()> {
  /// Sets [value] and awaits persistent storage without requiring an explicit `()` parameter.
  Future<T> setAsync(T value) => this.setAsync(value, const ());

  /// Updates the local state by applying [transform] without requiring an explicit `()` parameter.
  T update(T Function(T current) transform) => this.update(transform, const ());

  /// Resets the state back to [initialValue] without requiring an explicit `()` parameter.
  T reset() => this.reset(const ());

  /// Resets the state back to [initialValue] and awaits deletion from persistent storage without requiring an explicit `()` parameter.
  Future<T> resetAsync() => this.resetAsync(const ());
}
