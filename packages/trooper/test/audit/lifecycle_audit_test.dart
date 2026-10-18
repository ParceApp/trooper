@Tags(['audit'])
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _Controller extends TrooperController {
  _Controller(this.fetch);
  final Future<String> Function() fetch;

  late final q = query<String, ()>(namespace: 'lc_q', fetch: (_) => fetch());
  late final kq = keyedQuery<String, String, ()>(
      namespace: 'lc_kq', fetch: (_, __) => fetch());
  late final l = local<String, ()>(namespace: 'lc_l', initialValue: 'x');
  late final kl =
      keyedLocal<String, String, ()>(namespace: 'lc_kl', initialValue: 'x');
  late final s = stream<int, ()>(
      namespace: 'lc_s', streamFactory: (_, __) => Stream.periodic(
          const Duration(seconds: 1), (i) => i));
  late final m = mutation<String, ()>(
      namespace: 'lc_m', action: (_) => fetch());
}

typedef Disposable = ({
  String name,
  Object Function() create,
  Future<void> Function(Object) dispose,
  Future<void> Function(Object) use,
});

List<Disposable> disposables() {
  Future<String> fetch() async => 'v';
  return [
    (
      name: 'QueryTrooper',
      create: () => QueryTrooper<String, ()>(namespace: 'd_q', fetch: (_) => fetch()),
      dispose: (o) => (o as QueryTrooper<String, ()>).dispose(),
      use: (o) => (o as QueryTrooper<String, ()>).get(()),
    ),
    (
      name: 'KeyedQueryTrooper',
      create: () => KeyedQueryTrooper<String, String, ()>(
          namespace: 'd_kq', fetch: (_, __) => fetch()),
      dispose: (o) => (o as KeyedQueryTrooper<String, String, ()>).dispose(),
      use: (o) => (o as KeyedQueryTrooper<String, String, ()>)['k'].get(()),
    ),
    (
      name: 'LocalTrooper',
      create: () => LocalTrooper<String, ()>(namespace: 'd_l', initialValue: 'x'),
      dispose: (o) => (o as LocalTrooper<String, ()>).dispose(),
      use: (o) => (o as LocalTrooper<String, ()>).get(()),
    ),
    (
      name: 'KeyedLocalTrooper',
      create: () => KeyedLocalTrooper<String, String, ()>(
          namespace: 'd_kl', initialValue: 'x'),
      dispose: (o) => (o as KeyedLocalTrooper<String, String, ()>).dispose(),
      use: (o) => (o as KeyedLocalTrooper<String, String, ()>)['k'].get(()),
    ),
    (
      name: 'StreamTrooper',
      create: () => StreamTrooper<int, ()>(
          namespace: 'd_s',
          streamFactory: (_, __) =>
              Stream.periodic(const Duration(seconds: 1), (i) => i)),
      dispose: (o) => (o as StreamTrooper<int, ()>).dispose(),
      use: (o) => (o as StreamTrooper<int, ()>).get(()),
    ),
    (
      name: 'KeyedStreamTrooper',
      create: () => KeyedStreamTrooper<String, int, ()>(
          namespace: 'd_ks',
          streamFactory: (_, __, ___) =>
              Stream.periodic(const Duration(seconds: 1), (i) => i)),
      dispose: (o) => (o as KeyedStreamTrooper<String, int, ()>).dispose(),
      use: (o) => (o as KeyedStreamTrooper<String, int, ()>)['k'].get(()),
    ),
    (
      name: 'TrooperMutation',
      create: () => TrooperMutation<String, ()>(namespace: 'd_m', action: (_) => fetch()),
      dispose: (o) => (o as TrooperMutation<String, ()>).dispose(),
      use: (o) => (o as TrooperMutation<String, ()>).execute(()),
    ),
    (
      name: 'CacheStore',
      create: () => CacheStore(evictionInterval: const Duration(seconds: 1)),
      dispose: (o) => (o as CacheStore).dispose(),
      use: (o) async => (o as CacheStore).put<String>(const QueryKey('d_c', ()), 'v'),
    ),
    (
      name: 'TrooperQueryQueue',
      create: TrooperQueryQueue.new,
      dispose: (o) => (o as TrooperQueryQueue).dispose(),
      use: (o) => (o as TrooperQueryQueue)
          .execute<String>(key: const QueryKey('d_qq', ()), action: (_) => fetch()),
    ),
    (
      name: 'TrooperMutationQueue',
      create: TrooperMutationQueue.new,
      dispose: (o) => (o as TrooperMutationQueue).dispose(),
      use: (o) => (o as TrooperMutationQueue).add(fetch),
    ),
    (
      name: 'TrooperController',
      create: () => _Controller(fetch),
      dispose: (o) => (o as _Controller).dispose(),
      use: (o) => (o as _Controller).q.get(()),
    ),
  ];
}

const _useAfterDisposeFindings = {
  'LocalTrooper', 'KeyedLocalTrooper', 'StreamTrooper', 'KeyedStreamTrooper',
  'CacheStore',
};

void main() {
  for (final d in disposables()) {
    test('LIFE-01 ${d.name} dispose is idempotent', () async {
      final x = d.create();
      await d.use(x).then((_) {}, onError: (_) {});
      await d.dispose(x);
      await d.dispose(x);
    });

    test('LIFE-01 ${d.name} use after dispose fails with StateError', () async {
      final x = d.create();
      await d.dispose(x);
      await expectLater(Future.sync(() => d.use(x)), throwsStateError);
    }, skip: _useAfterDisposeFindings.contains(d.name) ? 'F-016' : null);

    test('LIFE-02 ${d.name} leaves no timers after dispose', () {
      fakeAsync((async) {
        final x = d.create();
        d.use(x).then((_) {}, onError: (_) {});
        async.elapse(const Duration(seconds: 2));
        d.dispose(x);
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty,
            reason: async.pendingTimersDebugString.join("\n"));
      });
    }, skip: d.name == 'KeyedStreamTrooper' ? 'F-017' : null);
  }

  test('LIFE-01 KeyedStreamTrooper dispose with active keys completes', () async {
    final sources = <String, StreamController<int>>{};
    final t = KeyedStreamTrooper<String, int, ()>(
      namespace: 'l01ks',
      streamFactory: (k, _, _) =>
          (sources[k] = StreamController<int>()).stream,
    );
    final subs = [
      t['a'].watch(initialParameter: (), eager: true).listen((_) {}),
      t['b'].watch(initialParameter: (), eager: true).listen((_) {}),
    ];
    await pumpEventQueue();
    sources['a']!.add(1);
    sources['b']!.add(2);
    await pumpEventQueue();
    await expectLater(t.dispose(), completes);
    for (final s in subs) {
      await s.cancel();
    }
  });

  test('LIFE-02 stream subscribers receive done after dispose', () async {
    final q = QueryTrooper<String, ()>(namespace: 'l02', fetch: (_) async => 'v');
    final done = Completer<void>();
    q.stream.listen((_) {}, onDone: done.complete);
    await q.get(());
    await q.dispose();
    await done.future.timeout(const Duration(seconds: 1));
  });

  test('LIFE-02 retry backoff timer does not outlive dispose', () {
    fakeAsync((async) {
      final q = QueryTrooper<String, ()>(
        namespace: 'l02r',
        fetch: (_) async => throw StateError('down'),
        config: const TrooperConfig(
          retryPolicy: RetryPolicy.exponential(
              maxRetries: 5, initialDelay: Duration(minutes: 1)),
        ),
      );
      q.get(()).then((_) {}, onError: (_) {});
      async.flushMicrotasks();
      q.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty,
          reason: async.pendingTimersDebugString.join("\n"));
    });
  }, skip: 'F-018');

  test('LIFE-04 controller dispose cascades with in-flight request', () async {
    final gate = Completer<String>();
    final c = _Controller(() => gate.future);
    final states = <StatefulData<String>>[];
    final errors = <Object>[];
    await runZonedGuarded(() async {
      c.q.stream.listen(states.add);
      c.q.get(()).then((_) {}, onError: (_) {});
      await pumpEventQueue();
      final before = states.length;
      await c.dispose();
      gate.complete('late');
      await pumpEventQueue();
      expect(c.q.isDisposed, isTrue);
      expect(states.length, before, reason: 'no state after dispose');
      expect(c.q.cache.get<String>(const QueryKey('lc_q', ())), isNull,
          reason: 'late result must not populate the cache');
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });
}
