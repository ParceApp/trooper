import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';
import 'package:trooper/src/telemetry/trooper_logger.dart';

/// Central dispatch bus for telemetry, logging, and DevTools diagnostic events.
///
/// Use [TelemetryHub.global] for application-wide logging and observation.
/// Isolated instances can be created for tests via [TelemetryHub.isolated].
///
/// ### Example:
/// ```dart
/// TelemetryHub.global.events.listen((event) {
///   if (event case RequestErrorEvent(:final key, :final error)) {
///     logToCrashlytics(key, error);
///   }
/// });
/// ```
class TelemetryHub with LifecycleAware {
  TelemetryHub._() {
    _controller = StreamController<TrooperEvent>.broadcast(sync: true);
  }

  /// Creates an isolated [TelemetryHub] instance for unit testing or scoped environments.
  @visibleForTesting
  factory TelemetryHub.isolated() => TelemetryHub._();

  /// Global default telemetry hub shared across the application.
  static final TelemetryHub global = TelemetryHub._();

  late final StreamController<TrooperEvent> _controller;
  bool _isDisposed = false;
  bool _isEmitting = false;
  final List<TrooperEvent> _pendingEvents = [];

  /// Stream emitting all diagnostic events recorded by this hub.
  Stream<TrooperEvent> get events => _controller.stream;

  /// Returns `true` if there are any active subscribers listening to this hub.
  bool get hasListeners => _controller.hasListener;

  /// Registers a [TrooperLogger] to receive all events emitted by this hub.
  void registerLogger(TrooperLogger logger) {
    if (_isDisposed) return;
    _controller.stream.listen(logger.log);
  }

  /// Emits a [TrooperEvent] to all registered listeners.
  ///
  /// If there are no active listeners, the event is immediately discarded at near-zero cost.
  void emit(TrooperEvent event) {
    if (_isDisposed || !_controller.hasListener) return;
    if (_isEmitting) {
      _pendingEvents.add(event);
      return;
    }
    _isEmitting = true;
    try {
      _controller.add(event);
      while (_pendingEvents.isNotEmpty) {
        if (_isDisposed || _controller.isClosed) break;
        _controller.add(_pendingEvents.removeAt(0));
      }
    } finally {
      _isEmitting = false;
    }
  }

  /// Evaluates [eventFactory] and emits the result only if there are active listeners.
  ///
  /// Avoids object allocation and string formatting overhead in production when
  /// telemetry logging is inactive.
  void emitLazy(TrooperEvent Function() eventFactory) {
    if (_isDisposed || !_controller.hasListener) return;
    emit(eventFactory());
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _pendingEvents.clear();
    if (_isEmitting) {
      scheduleMicrotask(() => _controller.close());
    } else {
      await _controller.close();
    }
  }
}
