import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperEvent & ConsoleTrooperLogger', () {
    final testKey = QueryKey('test_ns', (id: 42));

    test('all TrooperEvent variants produce informative toString outputs', () {
      final now = DateTime.now();
      final meta = DataMetadata.now(source: DataSource.network);

      final events = <TrooperEvent>[
        RequestStartedEvent(testKey, timestamp: now),
        CacheHitEvent(testKey, isFresh: true, metadata: meta, timestamp: now),
        SWRTriggeredEvent(testKey, timestamp: now),
        RequestCompletedEvent(
          testKey,
          duration: const Duration(milliseconds: 120),
          source: DataSource.network,
          timestamp: now,
        ),
        RequestErrorEvent(
          testKey,
          error: StateError('Network timeout'),
          duration: const Duration(milliseconds: 300),
          timestamp: now,
        ),
        PersistenceErrorEvent(
          testKey,
          error: 'Disk full',
          duration: const Duration(milliseconds: 10),
          timestamp: now,
        ),
        CacheInvalidatedEvent(testKey, timestamp: now),
        DataSetEvent(testKey, source: DataSource.local, timestamp: now),
      ];

      for (final event in events) {
        expect(event.toString(), contains('test_ns'));
        expect(event.timestamp, now);
      }
    });

    test('ConsoleTrooperLogger logs events via printFunction', () async {
      final printedLines = <String>[];
      final logger = ConsoleTrooperLogger(
        printFunction: (obj) => printedLines.add(obj.toString()),
        includeTimestamps: true,
      );

      final hub = TelemetryHub.isolated();
      final sub = logger.attach(hub);

      hub.emit(RequestStartedEvent(testKey));
      await Future<void>.delayed(Duration.zero);

      expect(printedLines.length, 1);
      expect(printedLines.first, contains('[Trooper:RequestStartedEvent]'));

      final nonTimestampLogger = ConsoleTrooperLogger(
        printFunction: (obj) => printedLines.add(obj.toString()),
        includeTimestamps: false,
      );
      nonTimestampLogger.log(CacheInvalidatedEvent(testKey));

      expect(printedLines.length, 2);
      expect(printedLines.last, startsWith('[Trooper:CacheInvalidatedEvent]'));

      await sub.cancel();
      hub.dispose();
    });

    test('TelemetryHub emitLazy, registerLogger, reentrancy and disposal', () async {
      final hub = TelemetryHub.isolated();
      var factoryCalled = false;

      // Lazy emission without listeners should not invoke factory
      hub.emitLazy(() {
        factoryCalled = true;
        return RequestStartedEvent(testKey);
      });
      expect(factoryCalled, isFalse);

      final received = <TrooperEvent>[];
      final logger = ConsoleTrooperLogger(
        printFunction: (obj) => received.add(RequestStartedEvent(testKey)),
      );
      hub.registerLogger(logger);
      expect(hub.hasListeners, isTrue);

      hub.emitLazy(() {
        factoryCalled = true;
        return RequestStartedEvent(testKey);
      });
      await Future<void>.delayed(Duration.zero);
      expect(factoryCalled, isTrue);
      expect(received.length, 1);

      // Re-entrant emission
      final reentrantHub = TelemetryHub.isolated();
      final order = <String>[];
      reentrantHub.events.listen((e) {
        order.add(e.runtimeType.toString());
        if (order.length == 1) {
          reentrantHub.emit(CacheInvalidatedEvent(testKey));
        }
      });

      reentrantHub.emit(RequestStartedEvent(testKey));
      await Future<void>.delayed(Duration.zero);
      expect(order, ['RequestStartedEvent', 'CacheInvalidatedEvent']);

      await reentrantHub.dispose();
      await hub.dispose();
    });
  });
}
