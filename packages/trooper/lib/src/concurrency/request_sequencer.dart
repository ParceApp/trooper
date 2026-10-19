import 'package:trooper/src/key/query_key.dart';

/// Orders responses per [QueryKey] so that an older response never replaces
/// a newer one, even when requests run in parallel.
///
/// Every request takes a sequence number via [begin] and settles it exactly
/// once via [settle]. A response may be applied to stream, cache and storage
/// only if no newer request for the same key has been applied before it.
final class RequestSequencer {
  int _last = 0;
  final Map<QueryKey, int> _inFlight = {};
  final Map<QueryKey, int> _applied = {};

  /// Registers a request for [key] and returns its sequence number.
  int begin(QueryKey key) {
    _inFlight[key] = (_inFlight[key] ?? 0) + 1;
    return ++_last;
  }

  /// Settles request [sequence] for [key] and returns whether its outcome may
  /// be applied.
  bool settle(QueryKey key, int sequence) {
    final mayApply = sequence > (_applied[key] ?? 0);
    final remaining = (_inFlight[key] ?? 1) - 1;
    if (remaining <= 0) {
      // Nothing left to order against: later requests get higher numbers.
      _inFlight.remove(key);
      _applied.remove(key);
    } else {
      _inFlight[key] = remaining;
      if (mayApply) _applied[key] = sequence;
    }
    return mayApply;
  }
}
