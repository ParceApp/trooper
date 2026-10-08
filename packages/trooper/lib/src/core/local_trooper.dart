import 'dart:async';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/trooper.dart';
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
///   name: 'app_theme',
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
        storage.write(key.storageKey, envelope.encode()).catchError(
          (Object error, StackTrace stackTrace) {
            telemetry.emit(
              PersistenceErrorEvent(
                key,
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
            key,
            error: error,
            duration: Duration.zero,
            stackTrace: stackTrace,
          ),
        );
        // Non-critical persistence failure
      }
    }

    return value;
  }

  /// Updates the local state by applying [transform] to the current value
  /// and returns the updated value.
  T update(T Function(T current) transform, P parameter) {
    final current = currentData(parameter) ?? initialValue;
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

    final storage = config.storage;
    if (storage != null) {
      storage.delete(key.storageKey).ignore();
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
    if (!_isHydrated && config.storage != null && codec != null) {
      final storage = config.storage!;
      final currentCodec = codec!;

      try {
        final serialized = await storage.read(key.storageKey);
        if (serialized != null) {
          final envelope = StorageEnvelope.tryDecode(serialized);
          if (envelope == null) {
            storage.delete(key.storageKey).ignore();
          } else if (envelope.isExpired) {
            storage.delete(key.storageKey).ignore();
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
      } catch (_) {
        // Corrupted storage entry
        storage.delete(key.storageKey).ignore();
      }

      _isHydrated = true;
    }

    return currentData(parameter) ?? initialValue;
  }

  @override
  StatefulStream<T> watch(P parameter, {bool eager = true}) {
    if (eager && !_isHydrated && config.storage != null && codec != null) {
      get(parameter).ignore();
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
  /// Updates the local state by applying [transform] without requiring an explicit `()` parameter.
  T update(T Function(T current) transform) => this.update(transform, const ());

  /// Resets the state back to [initialValue] without requiring an explicit `()` parameter.
  T reset() => this.reset(const ());
}
