import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _Opaque {
  const _Opaque(this.id);
  final String id;
}

class _Named {
  const _Named(this.id);
  final String id;
  @override
  String toString() => 'Named($id)';
}

void main() {
  group('QueryKey.storageKey', () {
    test('is versioned and URI-encodes each segment', () {
      expect(
        const QueryKey('a:b', (q: 'x:y')).storageKey,
        'trooper:1:a%3Ab:(q%3A%20x%3Ay)',
      );
      expect(
        const QueryKey.keyed('users', parameter: (), key: 'u:1').storageKey,
        'trooper:1:users:():u%3A1',
      );
    });

    test('namespaces sharing a prefix do not share a storage prefix', () {
      final a = const QueryKey('a', ()).storageKey;
      final ab = const QueryKey('a:b', ()).storageKey;
      expect(a.startsWith(QueryKey.storagePrefix('a')), isTrue);
      expect(ab.startsWith(QueryKey.storagePrefix('a')), isFalse);
    });

    test('flags parameters and keys without a stable toString', () {
      expect(const QueryKey('n', (f: _Named('A'))).hasStableStorageKey, isTrue);
      expect(
        const QueryKey('n', (f: _Opaque('A'))).hasStableStorageKey,
        isFalse,
      );
      expect(
        const QueryKey.keyed(
          'n',
          parameter: (),
          key: _Opaque('A'),
        ).hasStableStorageKey,
        isFalse,
      );
    });
  });

  group('L2 persistence by parameter', () {
    QueryTrooper<String, ({_Named f})> make(
      StorageBackend storage, {
      TelemetryHub? telemetry,
    }) => QueryTrooper(
      namespace: 'by_param',
      fetch: (p) async => 'data-for-${p.f.id}',
      codec: TrooperCodec.string,
      config: TrooperConfig(storage: storage),
      telemetry: telemetry,
    );

    test(
      'stable parameters are restored per value after a cold start',
      () async {
        final storage = InMemoryStorageBackend();
        final writer = make(storage);
        await writer.get((f: const _Named('A')));
        await writer.get((f: const _Named('B')));
        await pumpEventQueue();
        await writer.dispose();
        expect(storage.count, 2);

        // A parameter change always fetches, so read each value cold.
        var calls = 0;
        for (final id in ['A', 'B']) {
          final reader = QueryTrooper<String, ({_Named f})>(
            namespace: 'by_param',
            fetch: (_) async {
              calls++;
              return 'network';
            },
            codec: TrooperCodec.string,
            config: TrooperConfig(storage: storage),
          );
          expect(await reader.get((f: _Named(id))), 'data-for-$id');
          await reader.dispose();
        }
        expect(calls, 0);
      },
    );

    test('unstable parameters skip L2 and report it once', () async {
      final storage = InMemoryStorageBackend();
      final hub = TelemetryHub.isolated();
      final events = <PersistenceErrorEvent>[];
      hub.events
          .where((e) => e is PersistenceErrorEvent)
          .cast<PersistenceErrorEvent>()
          .listen(events.add);
      final q = QueryTrooper<String, ({_Opaque f})>(
        namespace: 'opaque',
        fetch: (p) async => p.f.id,
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
        telemetry: hub,
      );
      await q.get((f: const _Opaque('A')));
      await q.get((f: const _Opaque('B')));
      await pumpEventQueue();
      expect(storage.count, 0);
      expect(events, hasLength(1));
      expect(events.single.error, isA<TrooperStorageException>());
      await q.dispose();
    });
  });
}
