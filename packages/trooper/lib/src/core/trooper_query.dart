import 'dart:async';
import 'package:trooper/src/storage/cache_store.dart';
import 'package:trooper/src/codec/trooper_codec.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/query_queue.dart';
import 'package:trooper/src/config/stale_policy.dart';
import 'package:trooper/src/config/trooper_config.dart';
import 'package:trooper/src/core/trooper.dart';
import 'package:trooper/src/effects/trooper_side_effects.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// A query-based [Trooper] managing asynchronous data fetching, caching, and reactivity.
///
/// Features:
/// - **Request Coalescing**: Concurrent calls share a single network request.
/// - **Stale-While-Revalidate (SWR)**: Stale data is served immediately while revalidating in background.
/// - **L1 & L2 Caching**: In-memory caching with optional persistence via [TrooperConfig.storage] and [codec].
/// - **Reactive Stream**: Broadcasts [StatefulData] state transitions (`DataLoading`, `DataLoaded`, `DataRefreshing`, `DataError`).
///
/// ### Example:
/// ```dart
/// final userQuery = TrooperQuery<User, ({int id})>(
///   name: 'user',
///   fetch: (param) => fetchUserFromApi(param.id),
///   config: const TrooperConfig(timeToLive: Duration(minutes: 10)),
/// );
///
/// // Read with parameters:
/// final user = await userQuery.get((id: 42));
///
/// // Watch reactively:
/// userQuery.watch((id: 42)).listen((state) {
///   print(state);
/// });
/// ```
class TrooperQuery<T, P extends Parameter> extends Trooper<T, P> {
  /// Creates a [TrooperQuery] with a standard fetch function.
  factory TrooperQuery({
    required String namespace,
    required Future<T> Function(P param) fetch,
    TrooperCodec<T>? codec,
    TrooperConfig? config,
    TrooperSideEffects<T, P>? sideEffects,
    CacheStore? cache,
    TrooperQueryQueue? queryQueue,
    TelemetryHub? telemetry,
    StatefulStreamController<T>? streamController,
  }) => TrooperQuery.cancellable(
    namespace: namespace,
    fetch: (param, _) => fetch(param),
    codec: codec,
    config: config,
    sideEffects: sideEffects,
    cache: cache,
    queryQueue: queryQueue,
    telemetry: telemetry,
    streamController: streamController,
  );

  /// Creates a [TrooperQuery] with cooperative cancellation support via [TrooperCancelToken].
  TrooperQuery.cancellable({
    required super.namespace,
    required this.fetch,
    this.codec,
    super.config,
    super.sideEffects,
    super.cache,
    super.queryQueue,
    super.telemetry,
    super.streamController,
  });

  /// The underlying fetch function executed to retrieve data.
  final Future<T> Function(P param, TrooperCancelToken token) fetch;

  /// Optional codec used for serializing to / deserializing from [TrooperConfig.storage].
  final TrooperCodec<T>? codec;

  @override
  Future<T> get(P parameter, {bool forceRefresh = false}) async {
    final paramChanged = isParamChanged(parameter);
    recordParam(parameter);
    final key = buildQueryKey(parameter);

    // 1. Check L1 Memory Cache
    if (!forceRefresh && !paramChanged && config.hasCache) {
      final entry = cache.getEntry<T>(key);
      if (entry != null) {
        if (entry.isFresh) {
          if (telemetry.hasListeners) {
            telemetry.emit(
              CacheHitEvent(key, isFresh: true, metadata: entry.metadata),
            );
          }
          streamController.emitData(entry.data, metadata: entry.metadata);
          return entry.data;
        }

        // Stale entry found
        if (telemetry.hasListeners) {
          telemetry.emit(
            CacheHitEvent(key, isFresh: false, metadata: entry.metadata),
          );
        }

        if (config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
          if (telemetry.hasListeners) {
            telemetry.emit(SWRTriggeredEvent(key));
          }
          streamController.emitRefreshing(entry.data, metadata: entry.metadata);

          // Background revalidation (deduplicated by orchestrator)
          _executeFetch(
            key: key,
            param: parameter,
            forceRefresh: false,
            staleData: entry.data,
          ).ignore();

          return entry.data;
        }
      }

      // 2. Check L2 Storage only if L1 missed (entry == null)
      if (entry == null) {
        final storage = config.storage;
        final currentCodec = codec;
        if (storage != null && currentCodec != null) {
          final serialized = await storage.read(key.storageKey);
          if (serialized != null) {
            try {
              final restoredData = currentCodec.decode(serialized);
              cache.put(
                key,
                restoredData,
                timeToLive: config.timeToLive,
                source: DataSource.storage,
              );
              final restoredEntry = cache.getEntry<T>(key);
              if (telemetry.hasListeners) {
                telemetry.emit(
                  CacheHitEvent(
                    key,
                    isFresh: true,
                    metadata: restoredEntry?.metadata,
                  ),
                );
              }
              streamController.emitData(
                restoredData,
                metadata: restoredEntry?.metadata,
              );
              return restoredData;
            } catch (_) {
              storage.delete(key.storageKey).ignore();
            }
          }
        }
      }
    }

    // 3. Fall through to network fetch
    final staleData = cache.get<T>(key) ?? streamController.currentData;
    if (forceRefresh &&
        staleData != null &&
        config.stalePolicy == StalePolicy.keepStaleWhileRevalidate) {
      streamController.emitRefreshing(staleData);
    } else {
      streamController.emitLoading();
    }

    return await _executeFetch(
      key: key,
      param: parameter,
      forceRefresh: forceRefresh,
      staleData: staleData,
    );
  }

  Future<T> _executeFetch({
    required QueryKey key,
    required P param,
    required bool forceRefresh,
    T? staleData,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (telemetry.hasListeners) {
      telemetry.emit(RequestStartedEvent(key));
    }
    runSideEffect(() => sideEffects?.onRequestStarted?.call(param));

    try {
      var result = await queryQueue.execute<T>(
        key: key,
        forceRefresh: forceRefresh,
        deduplicate: config.deduplicate,
        conflictPolicy: config.conflictPolicy,
        action: (token) => fetch(param, token),
      );
      stopwatch.stop();
      if (sideEffects != null && sideEffects?.transformRequestResult != null) {
        runSideEffect(() async {
          T transformation = await sideEffects!.transformRequestResult!.call(
            result,
            param,
          );
          result = transformation;
        });
      }

      if (config.hasCache) {
        cache.put(
          key,
          result,
          timeToLive: config.timeToLive,
          source: DataSource.network,
        );
      }

      final entry = cache.getEntry<T>(key);
      streamController.emitData(result, metadata: entry?.metadata);

      // Persist to L2 storage asynchronously if configured
      final storage = config.storage;
      final currentCodec = codec;
      if (storage != null && currentCodec != null) {
        try {
          final serialized = currentCodec.encode(result);
          storage.write(key.storageKey, serialized).ignore();
        } catch (error, stacktrace) {
          telemetry.emit(
            PersistenceErrorEvent(
              key,
              error: error,
              duration: stopwatch.elapsed,
              stackTrace: stacktrace,
            ),
          );
          // Non-critical persistence failure
        }
      }

      if (telemetry.hasListeners) {
        telemetry.emit(
          RequestCompletedEvent(
            key,
            duration: stopwatch.elapsed,
            source: DataSource.network,
          ),
        );
      }

      runSideEffect(() => sideEffects?.onData?.call(result, param));

      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (telemetry.hasListeners) {
        telemetry.emit(
          RequestErrorEvent(
            key,
            error: error,
            duration: stopwatch.elapsed,
            stackTrace: stackTrace,
          ),
        );
      }

      streamController.emitError(
        error,
        stackTrace: stackTrace,
        staleData: staleData,
      );

      runSideEffect(() => sideEffects?.onError?.call(error, stackTrace, param));

      rethrow;
    }
  }
}
