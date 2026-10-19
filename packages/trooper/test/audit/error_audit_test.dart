@Tags(['audit'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

List<int> retryCallTimes(RetryPolicy policy) {
  final times = <int>[];
  fakeAsync((async) {
    final q = QueryTrooper<String, ()>(
      namespace: 'e03',
      fetch: (_) async {
        times.add(async.elapsed.inMilliseconds);
        throw StateError('down');
      },
      config: TrooperConfig(retryPolicy: policy),
    );
    q.get(()).then((_) {}, onError: (_) {});
    async.elapse(const Duration(minutes: 5));
    q.dispose();
    async.flushMicrotasks();
  });
  return times;
}

void main() {
  group('ERR-03 retry', () {
    test('exponential retry timing', () {
      expect(
        retryCallTimes(
          const RetryPolicy.exponential(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 100),
            jitter: 0,
          ),
        ),
        [0, 100, 300, 700],
      );
    });

    test('maxDelay clamps backoff', () {
      expect(
        retryCallTimes(
          const RetryPolicy.exponential(
            maxRetries: 3,
            initialDelay: Duration(milliseconds: 100),
            maxDelay: Duration(milliseconds: 250),
            jitter: 0,
          ),
        ),
        [0, 100, 300, 550],
      );
    });

    test('retryWhen false stops after first call', () {
      expect(
        retryCallTimes(
          RetryPolicy.exponential(maxRetries: 3, retryWhen: (_) => false),
        ),
        [0],
      );
    });

    test('backoff applies jitter (spec ERR-03)', () {
      // Two identical policies must not produce identical schedules when
      // jitter is applied; without jitter many clients retry in lockstep.
      final schedules = {
        for (var i = 0; i < 5; i++)
          retryCallTimes(
            const RetryPolicy.exponential(
              maxRetries: 3,
              initialDelay: Duration(milliseconds: 100),
            ),
          ).join(','),
      };
      expect(schedules.length, greaterThan(1));
    });
  });

  group('ERR-04/SEC-03 corrupt L2 entry falls back to fetch', () {
    const key = QueryKey('e04', ());
    final created = DateTime.now().toIso8601String();
    final cases = <(String, String)>[
      (
        'missing version (valid payload)',
        jsonEncode({'payload': '7', 'createdAt': created}),
      ),
      (
        'future version (valid payload)',
        jsonEncode({'version': 999, 'payload': '7', 'createdAt': created}),
      ),
      ('not json', 'not json'),
      (
        'wrong payload type',
        jsonEncode({
          'version': 1,
          'payload': 'not-an-int',
          'createdAt': created,
        }),
      ),
    ];
    for (final (label, raw) in cases) {
      test(label, () async {
        final storage = InMemoryStorageBackend();
        await storage.write(key.storageKey, raw);
        var calls = 0;
        final q = QueryTrooper<int, ()>(
          namespace: 'e04',
          fetch: (_) async {
            calls++;
            return 42;
          },
          codec: TrooperCodec.integer,
          config: TrooperConfig(storage: storage),
        );
        final errors = <Object>[];
        int? result;
        final done = Completer<void>();
        runZonedGuarded(() async {
          try {
            result = await q.get(());
            await pumpEventQueue();
          } catch (e) {
            errors.add(e);
          } finally {
            done.complete();
          }
        }, (e, _) => errors.add(e));
        await done.future;
        expect(errors, isEmpty);
        expect(result, 42, reason: 'L2 entry must not be used');
        expect(calls, 1);
        final stored = await storage.read(key.storageKey);
        expect(
          StorageEnvelope.tryDecode(stored!)?.version,
          StorageEnvelope.currentVersion,
        );
        await q.dispose();
      });
    }
  });

  test('ERR-02 corrupt L2 entry is reported via telemetry', () async {
    const key = QueryKey('e02', ());
    final storage = InMemoryStorageBackend();
    await storage.write(
      key.storageKey,
      jsonEncode({
        'version': 1,
        'payload': 'nope',
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );
    final hub = TelemetryHub.isolated();
    final events = <TrooperEvent>[];
    hub.events.listen(events.add);
    final q = QueryTrooper<int, ()>(
      namespace: 'e02',
      fetch: (_) async => 1,
      codec: TrooperCodec.integer,
      config: TrooperConfig(storage: storage),
      telemetry: hub,
    );
    await q.get(());
    await pumpEventQueue();
    expect(events.whereType<PersistenceErrorEvent>(), isNotEmpty);
    await q.dispose();
  });

  test('ERR-02 failing side effect is not swallowed silently', () async {
    final hub = TelemetryHub.isolated();
    final events = <TrooperEvent>[];
    hub.events.listen(events.add);
    final errors = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(() async {
      try {
        final q = QueryTrooper<String, ()>(
          namespace: 'e02s',
          fetch: (_) async => 'v',
          telemetry: hub,
          sideEffects: TrooperSideEffects(
            onData: (_, _) => throw StateError('side effect bug'),
          ),
        );
        await q.get(());
        await pumpEventQueue();
        await q.dispose();
      } finally {
        done.complete();
      }
    }, (e, _) => errors.add(e));
    await done.future;
    final surfaced =
        errors.isNotEmpty ||
        events.any((e) => '$e'.contains('side effect bug'));
    expect(surfaced, isTrue, reason: 'error must reach the zone or telemetry');
  });

  group('SEC-02 logging', () {
    Future<List<String>> logged(
      Future<void> Function(TelemetryHub) body,
    ) async {
      final hub = TelemetryHub.isolated();
      final out = <String>[];
      final sub = ConsoleTrooperLogger(
        printFunction: (o) => out.add('$o'),
      ).attach(hub: hub);
      await body(hub);
      await pumpEventQueue();
      await sub.cancel();
      return out;
    }

    test('logger does not print response payloads', () async {
      final out = await logged((hub) async {
        final q = QueryTrooper<String, ()>(
          namespace: 's02',
          fetch: (_) async => 'secret-123',
          telemetry: hub,
        );
        await q.get(());
        await q.dispose();
      });
      expect(out.join('\n'), isNot(contains('secret-123')));
    });

    test('logger does not print query parameters', () async {
      final out = await logged((hub) async {
        final q = QueryTrooper<String, ({String email})>(
          namespace: 's02p',
          fetch: (_) async => 'ok',
          telemetry: hub,
        );
        await q.get((email: 'jane@example.com'));
        await q.dispose();
      });
      expect(out.join('\n'), isNot(contains('jane@example.com')));
    });
  });
}
