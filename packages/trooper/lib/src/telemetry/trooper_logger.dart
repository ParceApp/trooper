import 'dart:async';
import 'package:trooper/src/key/query_key.dart';
import 'package:trooper/src/telemetry/telemetry_hub.dart';
import 'package:trooper/src/telemetry/trooper_event.dart';

/// Interface for consuming and recording [TrooperEvent] diagnostic logs.
abstract interface class TrooperLogger {
  /// Handles a diagnostic [event] dispatched by a [TelemetryHub].
  void log(TrooperEvent event);
}

/// A lightweight console logger that formats and prints [TrooperEvent] instances.
///
/// Response payloads are never printed. Query parameters and entity keys often
/// contain personal data (e-mail addresses, user IDs), so they are replaced by a
/// short hash by default, e.g. `QueryKey(users, parameter: #1f3a9c2e)`. Equal
/// values get equal hashes within and across runs, so log lines can still be
/// correlated. Set [logParameters] to print them in plain text, e.g. in local
/// debug builds. Messages of errors thrown by your own fetch code are printed
/// as they are.
class ConsoleTrooperLogger implements TrooperLogger {
  /// Creates a [ConsoleTrooperLogger].
  const ConsoleTrooperLogger({
    this.printFunction = print,
    this.includeTimestamps = true,
    this.logParameters = false,
  });

  /// The output function used for printing (defaults to [print]).
  final void Function(Object? object) printFunction;

  /// Whether to prefix log statements with an ISO-8601 timestamp.
  final bool includeTimestamps;

  /// Whether to print query parameters and entity keys in plain text instead
  /// of a hash. Defaults to `false`.
  final bool logParameters;

  @override
  void log(TrooperEvent event) {
    final prefix = includeTimestamps
        ? '[${event.timestamp.toIso8601String()}] '
        : '';
    var text = '$event';
    if (!logParameters) {
      final key = _keyOf(event);
      text = text.replaceAll(key.describe(), _maskedDescription(key));
    }
    printFunction('$prefix[Trooper:${event.runtimeType}] $text');
  }

  static QueryKey _keyOf(TrooperEvent event) => switch (event) {
    RequestStartedEvent(:final key) ||
    CacheHitEvent(:final key) ||
    SWRTriggeredEvent(:final key) ||
    RequestCompletedEvent(:final key) ||
    RequestErrorEvent(:final key) ||
    PersistenceErrorEvent(:final key) ||
    CacheInvalidatedEvent(:final key) ||
    DataSetEvent(:final key) => key,
  };

  /// [QueryKey.describe] with parameter and entity key replaced by a hash.
  static String _maskedDescription(QueryKey key) {
    final buffer = StringBuffer('QueryKey(${key.name}');
    if (key.parameter != const ()) {
      buffer.write(', parameter: #${_hash('${key.parameter}')}');
    }
    if (key.key != null) buffer.write(', key: #${_hash('${key.key}')}');
    buffer.write(')');
    return buffer.toString();
  }

  /// 32-bit FNV-1a, stable across runs (unlike [Object.hashCode]).
  static String _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Attaches this logger to [hub] (defaults to [TelemetryHub.global]).
  ///
  /// Returns a [StreamSubscription] that can be cancelled to stop logging.
  StreamSubscription<TrooperEvent> attach({TelemetryHub? hub}) {
    final targetHub = hub ?? TelemetryHub.global;
    return targetHub.events.listen(log);
  }
}
