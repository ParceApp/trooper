import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/storage/invalidatable.dart';
import 'package:trooper/src/concurrency/cancel_token.dart';
import 'package:trooper/src/concurrency/mutation_queue.dart';
import 'package:trooper/src/effects/trooper_mutation_side_effects.dart';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/types/parameter.dart';

/// A command-based mutation runner with automatic cache invalidation and queueing.
///
/// Features:
/// - **Automatic Invalidation**: Declaratively pass [invalidateOnSuccess] to invalidate
///   related queries or controllers upon successful completion.
/// - **Sequential Execution**: Optional [TrooperMutationQueue] guarantees strict FIFO order.
/// - **Reactive State**: Exposes [stream] with [StatefulData] transitions (`DataInitial`, `DataLoading`, `DataLoaded`, `DataError`).
/// - **Callable**: Can be executed directly via `mutation(param)` or `mutation.execute(param)`.
///
/// ### Example:
/// ```dart
/// final createLecture = TrooperMutation<Lecture, ({String title})>(
///   namespace: 'createLecture',
///   action: (param) => api.createLecture(param.title),
///   invalidateOnSuccess: [lectureQuery],
/// );
///
/// final lecture = await createLecture((title: 'Algorithms'));
/// ```
class TrooperMutation<T, P extends Parameter>
    with LifecycleAware
    implements Invalidatable {
  /// Creates a [TrooperMutation] with a standard action function.
  factory TrooperMutation({
    required String namespace,
    required Future<T> Function(P param) action,
    List<Invalidatable>? invalidateOnSuccess,
    TrooperMutationSideEffects<T, P>? sideEffects,
    TrooperMutationQueue? queue,
    TelemetryHub? telemetry,
    StatefulStreamController<T>? streamController,
  }) => TrooperMutation.cancellable(
    namespace: namespace,
    action: (param, _) => action(param),
    invalidateOnSuccess: invalidateOnSuccess,
    sideEffects: sideEffects,
    queue: queue,
    telemetry: telemetry,
    streamController: streamController,
  );

  /// Creates a [TrooperMutation] with cooperative cancellation support via [TrooperCancelToken].
  TrooperMutation.cancellable({
    required this.namespace,
    required this.action,
    this.invalidateOnSuccess,
    this.sideEffects,
    TrooperMutationQueue? queue,
    TelemetryHub? telemetry,
    StatefulStreamController<T>? streamController,
  }) : _ownsQueue = (queue == null),
       queue = queue ?? TrooperMutationQueue(),
       telemetry = telemetry ?? TelemetryHub.global,
       _streamController = streamController ?? StatefulStreamController<T>();

  final bool _ownsQueue;

  /// Logical name of this mutation.
  final String namespace;

  /// The underlying action function executed to perform the mutation.
  final Future<T> Function(P param, TrooperCancelToken token) action;

  /// Optional list of [Invalidatable] targets to invalidate on success.
  final List<Invalidatable>? invalidateOnSuccess;

  /// Optional side-effect callbacks for lifecycle hooks.
  final TrooperMutationSideEffects<T, P>? sideEffects;

  /// The FIFO queue sequencing mutation executions.
  final TrooperMutationQueue queue;

  /// Telemetry hub for diagnostic events.
  final TelemetryHub telemetry;

  final StatefulStreamController<T> _streamController;
  bool _isDisposed = false;

  /// Reactive stream reflecting the lifecycle state of this mutation.
  StatefulStream<T> get stream => _streamController.stream;

  /// The current state of this mutation.
  StatefulData<T> get currentState => _streamController.currentState;

  /// Returns `true` if a mutation is currently in-flight.
  bool get isLoading => _streamController.isLoading;

  /// Callable invocation shortcut: `mutation(param)`.
  Future<T> call(P parameter, {TrooperCancelToken? cancelToken}) =>
      execute(parameter, cancelToken: cancelToken);

  /// Executes this mutation with [parameter].
  Future<T> execute(P parameter, {TrooperCancelToken? cancelToken}) {
    if (_isDisposed) {
      throw StateError(
        'Cannot execute mutation on disposed TrooperMutation "$namespace"',
      );
    }

    final key = QueryKey(namespace, parameter);

    return queue.add<T>(() async {
      _streamController.emitLoading();
      if (telemetry.hasListeners) {
        telemetry.emit(RequestStartedEvent(key));
      }
      try {
        await sideEffects?.onStarted?.call(parameter);
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }

      final stopwatch = Stopwatch()..start();
      final effectiveCancelToken = cancelToken ?? TrooperCancelToken();

      try {
        final result = await action(parameter, effectiveCancelToken);
        // An action may ignore its token; a cancelled mutation must not
        // apply its result, invalidate targets or report success.
        effectiveCancelToken.throwIfCancelled();
        stopwatch.stop();

        _streamController.emitData(result);

        if (telemetry.hasListeners) {
          telemetry.emit(
            RequestCompletedEvent(
              key,
              duration: stopwatch.elapsed,
              source: DataSource.network,
            ),
          );
        }

        // Invalidate targets declaratively
        if (invalidateOnSuccess != null) {
          for (final target in invalidateOnSuccess!) {
            target.invalidate();
          }
        }

        try {
          await sideEffects?.onSuccess?.call(result, parameter);
        } catch (error, stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }

        return result;
      } catch (error, stackTrace) {
        stopwatch.stop();
        _streamController.emitError(error, stackTrace: stackTrace);

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

        try {
          await sideEffects?.onError?.call(error, stackTrace, parameter);
        } catch (callbackError, callbackStackTrace) {
          Zone.current.handleUncaughtError(callbackError, callbackStackTrace);
        }

        rethrow;
      }
    });
  }

  /// Resets the mutation state back to [DataInitial].
  void reset() {
    _streamController.emitInitial();
  }

  /// Invalidates this mutation by resetting its state back to [DataInitial].
  @override
  void invalidate() => reset();

  /// Resets mutation state to [DataInitial] on dependency changes.
  @override
  FutureOr<void> didChangeDependencies() {
    reset();
  }

  @override
  @mustCallSuper
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _streamController.dispose();
    if (_ownsQueue) {
      await queue.dispose();
    }
  }
}

/// Convenience extension for parameterless [TrooperMutation] instances where `P` is `()`.
extension ParameterlessTrooperMutation<T> on TrooperMutation<T, ()> {
  /// Callable invocation shortcut without requiring an explicit `()` parameter.
  Future<T> call({TrooperCancelToken? cancelToken}) =>
      this.execute(const (), cancelToken: cancelToken);

  /// Executes this mutation without requiring an explicit `()` parameter.
  Future<T> execute({TrooperCancelToken? cancelToken}) =>
      this.execute(const (), cancelToken: cancelToken);
}
