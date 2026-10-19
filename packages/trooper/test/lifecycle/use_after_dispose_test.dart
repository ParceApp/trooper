import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _SharedController extends TrooperController {
  _SharedController()
    : super(defaultQueryQueue: TrooperQueryQueue(), defaultCache: CacheStore());

  late final q = query<String, ()>(
    namespace: 'uad_shared_q',
    fetch: (_) async => 'v',
  );
}

void main() {
  group('use after dispose (LifecycleAware contract)', () {
    test('trigger throws synchronously instead of failing silently', () async {
      final q = QueryTrooper<String, ()>(
        namespace: 'uad_trigger',
        fetch: (_) async => 'v',
      );
      await q.dispose();
      expect(() => q.trigger(()), throwsStateError);
      expect(() => q.watch(initialParameter: ()), throwsStateError);
    });

    test('query on a shared queue fails after its own dispose', () async {
      final c = _SharedController();
      expect(await c.q.get(()), 'v');
      await c.q.dispose();
      await expectLater(c.q.get(()), throwsStateError);
      await c.dispose();
    });

    test('snapshots return the last state after dispose', () async {
      final l = LocalTrooper<String, ()>(namespace: 'uad_l', initialValue: 'x');
      l.set('y', ());
      await l.dispose();
      expect(l.currentData(), 'y');
      expect(l.current(), isA<DataLoaded<String>>());
      expect(l.isDisposed, isTrue);
    });

    test('invalidate and lifecycle hooks are no-ops after dispose', () async {
      final q = QueryTrooper<String, ()>(
        namespace: 'uad_noop',
        fetch: (_) async => 'v',
      );
      final kq = KeyedQueryTrooper<int, String, ()>(
        namespace: 'uad_noop_k',
        fetch: (k, _) async => '$k',
      );
      final s = StreamTrooper<int, ()>(
        namespace: 'uad_noop_s',
        streamFactory: (_, _) => const Stream.empty(),
      );
      final m = TrooperMutation<String, ()>(
        namespace: 'uad_noop_m',
        action: (_) async => 'v',
      );
      await q.get(());
      await kq.getKey(1, ());
      await q.dispose();
      await kq.dispose();
      await s.dispose();
      await m.dispose();

      for (final target in <Object>[q, kq, s, m]) {
        (target as Invalidatable).invalidate();
        final lifecycle = target as LifecycleAware;
        await lifecycle.pause();
        await lifecycle.resume();
        await lifecycle.recover();
        await lifecycle.didChangeDependencies();
      }
      kq.invalidateKey(1);
      await kq.removeKey(1);
      await kq.clearAll();
      expect(q.currentData(), 'v', reason: 'invalidate did not reset state');
    });

    test('invalidateOnSuccess skips disposed targets', () async {
      final target = QueryTrooper<String, ()>(
        namespace: 'uad_inv_target',
        fetch: (_) async => 'v',
      );
      final m = TrooperMutation<String, ()>(
        namespace: 'uad_inv_m',
        action: (_) async => 'done',
        invalidateOnSuccess: [target],
      );
      await target.dispose();
      expect(await m(()), 'done');
      await m.dispose();
    });

    test('LoadMore rejects new work after dispose', () async {
      final source = QueryTrooper<List<int>, ({() filter, int page})>(
        namespace: 'uad_lm',
        fetch: (p) async => [p.page],
      );
      final feed = LoadMore<List<int>, (), int>(
        source: source,
        initialPageParam: 1,
        nextPageParam: (last, all) => all.length + 1,
      );
      await feed.dispose();
      await expectLater(feed.get(()), throwsStateError);
      expect(() => feed.trigger(()), throwsStateError);
      await expectLater(feed.fetchNextPage(), throwsStateError);
      feed.invalidate();
      await source.dispose();
    });

    test('controller lifecycle drivers are no-ops after dispose', () async {
      final c = _SharedController();
      await c.dispose();
      await c.initialize();
      await c.pause();
      await c.resume();
      await c.recover();
      await c.didChangeDependencies();
      c.invalidate();
      c.clearAll();
    });
  });
}
