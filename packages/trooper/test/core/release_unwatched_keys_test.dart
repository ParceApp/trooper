import 'dart:async';

import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _Controller extends TrooperController {
  late final users = keyedQuery<String, String, ()>(
    namespace: 'rel_ctrl',
    fetch: (k, _) async => 'user-$k',
    releaseUnwatchedKeys: true,
  );
  late final rooms = keyedStream<String, String, ()>(
    namespace: 'rel_ctrl_rooms',
    streamFactory: (_, _, _) => const Stream<String>.empty(),
    releaseUnwatchedKeys: true,
  );
}

void main() {
  group('KeyedQueryTrooper releaseUnwatchedKeys', () {
    late int fetches;
    KeyedQueryTrooper<String, String, ()> query({
      bool release = true,
      Future<String> Function(String key)? fetch,
    }) {
      fetches = 0;
      return KeyedQueryTrooper<String, String, ()>(
        namespace: 'rel_q',
        fetch: (k, _) {
          fetches++;
          return fetch?.call(k) ?? Future.value('user-$k');
        },
        releaseUnwatchedKeys: release,
      );
    }

    test(
      'drops per-key state after the last listener, keeps L1 data',
      () async {
        final q = query();
        final sub = q
            .watchKey('a', initialParameter: (), eager: true)
            .listen((_) {});
        await pumpEventQueue();
        expect(q.currentKeyData('a'), 'user-a');

        await sub.cancel();
        await pumpEventQueue();

        expect(q.stream.containsKey('a'), isFalse);
        expect(q.lastParamOf('a'), isNull);
        expect(q.currentKeyData('a'), isNull);
        expect(await q.getKey('a', ()), 'user-a');
        expect(fetches, 1, reason: 'served from the L1 cache');
        await q.dispose();
      },
    );

    test('is off by default', () async {
      final q = query(release: false);
      final sub = q
          .watchKey('a', initialParameter: (), eager: true)
          .listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
      await pumpEventQueue();

      expect(q.stream.containsKey('a'), isTrue);
      expect(q.currentKeyData('a'), 'user-a');
      await q.dispose();
    });

    test(
      'releases a key read only via getKey once the request is done',
      () async {
        final pending = Completer<String>();
        final q = query(fetch: (_) => pending.future);
        final result = q.getKey('a', ());
        await pumpEventQueue();
        expect(q.stream.containsKey('a'), isTrue, reason: 'request in flight');

        pending.complete('late');
        expect(await result, 'late');
        await pumpEventQueue();
        expect(q.stream.containsKey('a'), isFalse);
        await q.dispose();
      },
    );

    test('keeps a key that is re-watched in the same tick', () async {
      final q = query();
      final first = q
          .watchKey('a', initialParameter: (), eager: true)
          .listen((_) {});
      await pumpEventQueue();
      // Like a StreamBuilder that resubscribes synchronously on rebuild.
      unawaited(first.cancel());
      final second = q.watchKey('a').listen((_) {});
      await pumpEventQueue();

      expect(q.currentKeyData('a'), 'user-a');
      await second.cancel();
      await q.dispose();
    });

    test('keeps all keys while watchAll has a listener', () async {
      final q = query();
      final all = q.stream.watchAll().listen((_) {});
      await q.getKey('a', ());
      await pumpEventQueue();

      expect(q.stream.containsKey('a'), isTrue);
      await all.cancel();
      await q.dispose();
    });
  });

  group('KeyedStreamTrooper releaseUnwatchedKeys', () {
    late StreamController<String> source;
    setUp(() => source = StreamController<String>.broadcast());
    tearDown(() => source.close());

    KeyedStreamTrooper<String, String, ()> trooper({bool keepAlive = false}) =>
        KeyedStreamTrooper<String, String, ()>(
          namespace: 'rel_s',
          streamFactory: (_, _, _) => source.stream,
          keepAlive: keepAlive,
          releaseUnwatchedKeys: true,
        );

    test('drops per-key state after the last watcher disconnects', () async {
      final t = trooper();
      final sub = t.watchKey('room', initialParameter: ()).listen((_) {});
      await pumpEventQueue();
      source.add('hello');
      await pumpEventQueue();
      expect(t.currentKeyData('room'), 'hello');

      await sub.cancel();
      await pumpEventQueue();

      expect(t.isConnectedKey('room'), isFalse);
      expect(t.stream.containsKey('room'), isFalse);
      await t.dispose();
    });

    test('keeps the key while keepAlive holds the connection', () async {
      final t = trooper(keepAlive: true);
      final sub = t.watchKey('room', initialParameter: ()).listen((_) {});
      await pumpEventQueue();
      source.add('hello');
      await pumpEventQueue();
      await sub.cancel();
      await pumpEventQueue();

      expect(t.stream.containsKey('room'), isTrue);
      await t.dispose();
    });
  });

  test('TrooperController factories forward releaseUnwatchedKeys', () async {
    final c = _Controller();
    final sub = c.users
        .watchKey('a', initialParameter: (), eager: true)
        .listen((_) {});
    await pumpEventQueue();
    await sub.cancel();
    await pumpEventQueue();

    expect(c.users.stream.containsKey('a'), isFalse);
    expect(c.rooms.releaseUnwatchedKeys, isTrue);
    await c.dispose();
  });
}
