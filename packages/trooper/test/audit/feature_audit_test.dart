@Tags(['audit'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

/// No state without data may appear between two loaded states (zero flicker).
void expectNoFlicker<T>(List<StatefulData<T>> states) {
  var seenData = false;
  for (final s in states) {
    if (s is DataLoaded<T>) {
      seenData = true;
    } else if (seenData) {
      fail('state without data after data was shown: $s in $states');
    }
  }
}

class _SharedQueueController extends TrooperController {
  _SharedQueueController(TrooperQueryQueue queue, this.fetch)
    : super(defaultQueryQueue: queue);
  final Future<String> Function() fetch;
  late final profile = query<String, ()>(
    namespace: 'f03_shared',
    fetch: (_) => fetch(),
  );
}

class _Filter {
  const _Filter(this.id);
  final String id;
  @override
  bool operator ==(Object other) => other is _Filter && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

void main() {
  group('FEAT-02 SWR without flicker', () {
    test('QueryTrooper refresh keeps data visible', () async {
      var n = 0;
      final q = QueryTrooper<String, ()>(
        namespace: 'f02q',
        fetch: (_) async => 'v${n++}',
      );
      final states = <StatefulData<String>>[];
      q.stream.listen(states.add);
      await q.get(());
      await q.refresh(());
      await pumpEventQueue();
      expectNoFlicker(states);
      expect(states.whereType<DataRefreshing<String>>(), isNotEmpty);
      await q.dispose();
    });

    test('KeyedQueryTrooper refresh keeps data visible', () async {
      var n = 0;
      final q = KeyedQueryTrooper<String, String, ()>(
        namespace: 'f02k',
        fetch: (k, _) async => '$k${n++}',
      );
      final states = <StatefulData<String>>[];
      q['a'].stream.listen(states.add);
      await q['a'].get(());
      await q['a'].refresh(());
      await pumpEventQueue();
      expectNoFlicker(states);
      await q.dispose();
    });

    test('StreamTrooper refresh keeps data visible', () async {
      final sources = <StreamController<int>>[];
      final t = StreamTrooper<int, ()>(
        namespace: 'f02s',
        streamFactory: (_, _) {
          final c = StreamController<int>();
          sources.add(c);
          scheduleMicrotask(() => c.add(sources.length));
          return c.stream;
        },
      );
      final states = <StatefulData<int>>[];
      t.stream.listen(states.add);
      await t.get(());
      await t.refresh(());
      await pumpEventQueue();
      expectNoFlicker(states);
      await t.dispose();
    });
  });

  group('FEAT-03 coalescing', () {
    for (final n in [2, 50]) {
      test('$n parallel gets share one fetch', () async {
        var calls = 0;
        final gate = Completer<String>();
        final q = QueryTrooper<String, ()>(
          namespace: 'f03_$n',
          fetch: (_) {
            calls++;
            return gate.future;
          },
        );
        final futures = [for (var i = 0; i < n; i++) q.get(())];
        gate.complete('v');
        expect(await Future.wait(futures), everyElement('v'));
        expect(calls, 1);
        await q.dispose();
      });
    }

    test(
      'two controllers sharing a TrooperQueryQueue share one fetch',
      () async {
        var calls = 0;
        final gate = Completer<String>();
        Future<String> fetch() {
          calls++;
          return gate.future;
        }

        final queue = TrooperQueryQueue();
        final a = _SharedQueueController(queue, fetch);
        final b = _SharedQueueController(queue, fetch);
        final fa = a.profile.get(());
        final fb = b.profile.get(());
        gate.complete('v');
        expect(await fa, 'v');
        expect(await fb, 'v');
        expect(calls, 1);
        await a.dispose();
        await b.dispose();
        await queue.dispose();
      },
    );
  });

  group('FEAT-05 L1/L2 interplay', () {
    test('cold start restores fresh data from L2 without fetching', () async {
      final storage = InMemoryStorageBackend();
      final first = QueryTrooper<String, ()>(
        namespace: 'f05',
        fetch: (_) async => 'network',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );
      await first.get(());
      await pumpEventQueue();
      await first.dispose();

      var calls = 0;
      final second = QueryTrooper<String, ()>(
        namespace: 'f05',
        fetch: (_) async {
          calls++;
          return 'network-2';
        },
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );
      expect(await second.get(()), 'network');
      expect(calls, 0);
      await second.dispose();
    });

    test('L2 keys of different parameters do not collide', () async {
      final storage = InMemoryStorageBackend();
      QueryTrooper<String, ({_Filter f})> make() => QueryTrooper(
        namespace: 'f05k',
        fetch: (p) async => 'data-for-${p.f.id}',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );
      final writer = make();
      await writer.get((f: const _Filter('B')));
      await pumpEventQueue();
      await writer.dispose();

      final reader = make(); // cold start
      expect(await reader.get((f: const _Filter('A'))), 'data-for-A');
      await reader.dispose();
    });

    test('fetch result is written through to L2', () async {
      final storage = InMemoryStorageBackend();
      final q = QueryTrooper<String, ()>(
        namespace: 'f05w',
        fetch: (_) async => 'network',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );
      await q.get(());
      await pumpEventQueue();
      final raw = await storage.read(const QueryKey('f05w', ()).storageKey);
      expect(StorageEnvelope.tryDecode(raw!)?.payload, 'network');
      await q.dispose();
    });
  });
}
