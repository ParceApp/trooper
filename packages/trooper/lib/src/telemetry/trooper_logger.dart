import 'dart:async';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';

/// Interface for consuming and recording [TrooperEvent] diagnostic logs.
abstract interface class TrooperLogger {
  /// Handles a diagnostic [event] dispatched by a [TelemetryHub].
  void log(TrooperEvent event);
}

/// A lightweight console logger that formats and prints [TrooperEvent] instances.
class ConsoleTrooperLogger implements TrooperLogger {
  /// Creates a [ConsoleTrooperLogger].
  const ConsoleTrooperLogger({
    this.printFunction = print,
    this.includeTimestamps = true,
  });

  /// The output function used for printing (defaults to [print]).
  final void Function(Object? object) printFunction;

  /// Whether to prefix log statements with an ISO-8601 timestamp.
  final bool includeTimestamps;

  @override
  void log(TrooperEvent event) {
    final prefix = includeTimestamps
        ? '[${event.timestamp.toIso8601String()}] '
        : '';
    printFunction('$prefix[Trooper:${event.runtimeType}] $event');
  }

  /// Attaches this logger to [hub] (defaults to [TelemetryHub.global]).
  ///
  /// Returns a [StreamSubscription] that can be cancelled to stop logging.
  StreamSubscription<TrooperEvent> attach({TelemetryHub? hub}) {
    final targetHub = hub ?? TelemetryHub.global;
    return targetHub.events.listen(log);
  }
}
