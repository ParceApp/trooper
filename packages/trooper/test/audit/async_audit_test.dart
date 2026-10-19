@Tags(['audit'])
library;

import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

/// Runs [body] and collects every uncaught error of its zone.
Future<List<Object>> collectZoneErrors(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
    } catch (e) {
      errors.add(e);
    } finally {
      done.complete();
    }
  }, (e, _) => errors.add(e));
  await done.future;
  // Let trailing microtasks surface their errors.
  await Future<void>.value();
  return errors;
}

/// Fetch whose calls are resolved manually, in any order.
class ManualFetch<T> {
  final calls = <Completer<T>>[];
  Future<T> call() {
    final c = Completer<T>();
    calls.add(c);
    return c.future;
  }
}

class _StorageController extends TrooperController {
  _StorageController(StorageBackend storage) : super(defaultStorage: storage);
  late final profile = query<String, ()>(
    namespace: 'a02c_profile',
    fetch: (_) async => 'jane@example.com',
    codec: TrooperCodec.string,
  );
}

class _KeyedStorageController extends TrooperController {
  _KeyedStorageController(StorageBackend storage)
    : super(defaultStorage: storage);
  late final contacts = keyedQuery<String, String, ()>(
    namespace: 'a02c_contacts',
    fetch: (k, _) async => '$k@example.com',
    codec: TrooperCodec.string,
  );
}

void main() {
  group('ASYNC-01 older response never overwrites newer', () {
    for (final policy in QueryConflictPolicy.values) {
      test('QueryTrooper, $policy', () async {
        final fetch = ManualFetch<String>();
        final q = QueryTrooper<String, ()>(
          namespace: 'a01_$policy',
          fetch: (_) => fetch(),
          config: TrooperConfig(deduplicate: false, conflictPolicy: policy),
        );
        final f0 = q.get((), forceRefresh: true);
        final f1 = q.get((), forceRefresh: true);
        f0.ignore();
        f1.ignore();
        await Future<void>.value();
        expect(fetch.calls, hasLength(2));
        fetch.calls[1].complete('new');
        await pumpEventQueue();
        if (!fetch.calls[0].isCompleted) fetch.calls[0].complete('old');
        await pumpEventQueue();

        expect(q.currentData(), 'new');
        expect(q.cache.get<String>(QueryKey('a01_$policy', ())), 'new');
        await q.dispose();
      });
    }

    for (final policy in QueryConflictPolicy.values) {
      test('KeyedQueryTrooper, $policy', () async {
        final fetch = ManualFetch<String>();
        final q = KeyedQueryTrooper<String, String, ()>(
          namespace: 'a01k_$policy',
          fetch: (_, _) => fetch(),
          config: TrooperConfig(deduplicate: false, conflictPolicy: policy),
        );
        final f0 = q['k'].get((), forceRefresh: true);
        final f1 = q['k'].get((), forceRefresh: true);
        f0.ignore();
        f1.ignore();
        await Future<void>.value();
        expect(fetch.calls, hasLength(2));
        fetch.calls[1].complete('new');
        await pumpEventQueue();
        if (!fetch.calls[0].isCompleted) fetch.calls[0].complete('old');
        await pumpEventQueue();

        expect(q['k'].currentData(), 'new');
        await q.dispose();
      });
    }
  });

  group('ASYNC-02 operations during an in-flight request', () {
    test(
      'invalidate: caller gets TrooperCancelledException, late result is dropped',
      () async {
        final fetch = ManualFetch<String>();
        final q = QueryTrooper<String, ()>(
          namespace: 'a02i',
          fetch: (_) => fetch(),
        );
        final f = q.get(());
        await Future<void>.value();
        q.invalidate();
        fetch.calls.single.complete('late');
        await expectLater(f, throwsA(isA<TrooperCancelledException>()));
        await pumpEventQueue();
        expect(q.current(), isA<DataInitial<String>>());
        expect(q.cache.get<String>(const QueryKey('a02i', ())), isNull);
        await q.dispose();
      },
    );

    test('refresh (forward): first caller receives the newer result', () async {
      // Documented: "forwards awaiting callers to the new request".
      // The superseded fetch ignores its cancel token and resolves first.
      final fetch = ManualFetch<String>();
      final q = QueryTrooper<String, ()>(
        namespace: 'a02r',
        fetch: (_) => fetch(),
      );
      final states = <StatefulData<String>>[];
      q.stream.listen(states.add);
      final f0 = q.get(());
      await Future<void>.value();
      final f1 = q.refresh(());
      await Future<void>.value();
      fetch.calls.first.complete('old');
      await pumpEventQueue();
      fetch.calls.last.complete('new');
      expect(await f0, 'new');
      expect(await f1, 'new');
      expect(
        states.whereType<DataLoaded<String>>().map((s) => s.data),
        isNot(contains('old')),
        reason: 'superseded result must not reach the stream',
      );
      await q.dispose();
    }, skip: 'F-013');

    test(
      'mutation invalidateOnSuccess: late query result is not cached',
      () async {
        final fetch = ManualFetch<String>();
        final q = QueryTrooper<String, ()>(
          namespace: 'a02m',
          fetch: (_) => fetch(),
        );
        final m = TrooperMutation<String, ()>(
          namespace: 'a02m_m',
          action: (_) async => 'saved',
          invalidateOnSuccess: [q],
        );
        q.get(()).then((_) {}, onError: (_) {});
        await Future<void>.value();
        await m.execute(());
        fetch.calls.single.complete('pre-mutation');
        await pumpEventQueue();
        expect(q.cache.get<String>(const QueryKey('a02m', ())), isNull);
        expect(q.currentData(), isNot('pre-mutation'));
        await q.dispose();
        await m.dispose();
      },
    );

    test('invalidate removes L2 storage as documented', () async {
      final storage = InMemoryStorageBackend();
      final q = QueryTrooper<String, ()>(
        namespace: 'a02s',
        fetch: (_) async => 'v',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );
      await q.get(());
      await pumpEventQueue();
      expect(await storage.getAllKeys(), isNotEmpty);
      q.invalidate();
      await pumpEventQueue();
      expect(await storage.getAllKeys(), isEmpty);
      await q.dispose();
    });
    test('controller.clearAll removes persisted QueryTrooper data', () async {
      final storage = InMemoryStorageBackend();
      final c = _StorageController(storage);
      await c.profile.get(());
      await pumpEventQueue();
      expect(await storage.getAllKeys(), isNotEmpty);
      c.clearAll();
      await pumpEventQueue();
      expect(
        await storage.getAllKeys(),
        isEmpty,
        reason: 'e.g. logout via clearAll must not leave user data on disk',
      );
      await c.dispose();
    });
    test(
      'controller.clearAll removes persisted KeyedQueryTrooper data',
      () async {
        final storage = InMemoryStorageBackend();
        final c = _KeyedStorageController(storage);
        await c.contacts['a'].get(());
        await pumpEventQueue();
        expect(await storage.getAllKeys(), isNotEmpty);
        c.clearAll();
        await pumpEventQueue();
        expect(await storage.getAllKeys(), isEmpty);
        await c.dispose();
      },
    );

    test(
      'keyed invalidate purges L2 entries from an earlier session',
      () async {
        final storage = InMemoryStorageBackend();
        final first = _KeyedStorageController(storage);
        await first.contacts['a'].get(());
        await pumpEventQueue();
        await first.dispose();
        // next app session: same storage, nothing in memory yet
        final second = _KeyedStorageController(storage);
        second.contacts.invalidate();
        await pumpEventQueue();
        expect(await storage.getAllKeys(), isEmpty);
        await second.dispose();
      },
    );
  });

  test('ASYNC-03 failing SWR background revalidation is observable', () async {
    final hub = TelemetryHub.isolated();
    final events = <TrooperEvent>[];
    hub.events.listen(events.add);
    final q = QueryTrooper<String, ()>(
      namespace: 'a03',
      fetch: (_) async => throw StateError('backend down'),
      telemetry: hub,
    );
    final past = DateTime.now().subtract(const Duration(hours: 1));
    q.cache.putEntry(
      const QueryKey('a03', ()),
      CacheEntry<String>('stale', createdAt: past, expiresAt: past),
    );
    final states = <StatefulData<String>>[];
    q.stream.listen(states.add);

    final errors = await collectZoneErrors(() async {
      expect(await q.get(()), 'stale');
      await pumpEventQueue();
    });

    expect(errors, isEmpty);
    expect(
      states.whereType<DataError<String>>().map((s) => s.staleData),
      contains('stale'),
    );
    expect(events.whereType<RequestErrorEvent>(), isNotEmpty);
    await q.dispose();
  });

  test(
    'ASYNC-04 listener may invalidate and dispose during notification',
    () async {
      final q = QueryTrooper<String, ()>(
        namespace: 'a04',
        fetch: (_) async => 'v',
      );
      final errors = await collectZoneErrors(() async {
        q.stream.listen((s) {
          if (s is DataLoaded<String>) {
            q.invalidate();
            q.dispose();
          }
        });
        await q.get(());
        await pumpEventQueue();
      });
      expect(errors, isEmpty);
      expect(q.isDisposed, isTrue);
    },
  );

  test('ASYNC-05 QueryTrooper: no state from a cancelled request', () async {
    final fetch = ManualFetch<String>();
    final q = QueryTrooper<String, ({String t})>.cancellable(
      namespace: 'a05',
      fetch: (p, token) => fetch(),
      config: const TrooperConfig(conflictPolicy: QueryConflictPolicy.cancel),
    );
    final states = <StatefulData<String>>[];
    q.stream.listen(states.add);
    q.get((t: 'a')).ignore();
    await Future<void>.value();
    q.get((t: 'b')).ignore();
    await Future<void>.value();
    fetch.calls[1].complete('b');
    await pumpEventQueue();
    fetch.calls[0].complete('a');
    await pumpEventQueue();

    expect(
      states.whereType<DataLoaded<String>>().map((s) => s.data),
      isNot(contains('a')),
    );
    expect(q.currentData(), 'b');
    await q.dispose();
  });

  test('ASYNC-05 TrooperMutation: no DataLoaded after cancel', () async {
    final done = Completer<String>();
    final m = TrooperMutation<String, ()>.cancellable(
      namespace: 'a05m',
      action: (_, token) => done.future,
    );
    final token = TrooperCancelToken();
    final f = m.execute((), cancelToken: token)..ignore();
    await Future<void>.value();
    token.cancel(reason: 'user left');
    done.complete('result');
    await pumpEventQueue();
    await f.then((_) {}, onError: (_) {});

    expect(m.currentState, isNot(isA<DataLoaded<String>>()));
    await m.dispose();
  }, skip: 'F-015');

  test('ASYNC-06 mutation queue serializes in submission order', () async {
    final queue = TrooperMutationQueue();
    final started = <int>[];
    final ended = <int>[];
    final gates = List.generate(3, (_) => Completer<void>());
    final futures = [
      for (var i = 0; i < 3; i++)
        queue.add(() async {
          started.add(i);
          await gates[i].future;
          ended.add(i);
          return i;
        }),
    ];
    await pumpEventQueue();
    expect(started, [0]);
    gates[2].complete();
    gates[1].complete();
    await pumpEventQueue();
    expect(started, [0], reason: 'task 1 must wait for task 0');
    gates[0].complete();
    expect(await Future.wait(futures), [0, 1, 2]);
    expect(started, [0, 1, 2]);
    expect(ended, [0, 1, 2]);
    await queue.dispose();
  });

  test('ASYNC-07 randomized interleavings keep last-issued result', () {
    for (var seed = 0; seed < 1000; seed++) {
      fakeAsync((async) {
        final rnd = Random(seed);
        var seq = 0;
        int? expected;
        final q = QueryTrooper<int, ()>(
          namespace: 'a07_$seed',
          fetch: (_) async {
            final mine = seq++;
            await Future<void>.delayed(Duration(milliseconds: rnd.nextInt(50)));
            return mine;
          },
        );
        for (var op = 0; op < 20; op++) {
          switch (rnd.nextInt(3)) {
            case 0:
              expected = seq;
              q.refresh(()).ignore();
            case 1:
              expected = seq;
              q.get((), forceRefresh: true).ignore();
            default:
              // invalidate cancels in-flight requests and resets to initial
              q.invalidate();
              expected = null;
          }
          async.elapse(Duration(milliseconds: rnd.nextInt(20)));
        }
        async.flushTimers();
        expect(q.currentData(), expected, reason: 'seed $seed');
        expect(q.queryQueue.activeCount, 0, reason: 'seed $seed');
        q.dispose();
        async.flushMicrotasks();
      });
    }
  });
}
