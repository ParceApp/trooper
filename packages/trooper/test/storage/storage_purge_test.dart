import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/delegating_storage_backend.dart';

QueryTrooper<String, ()> _query(
  StorageBackend storage,
  String namespace, {
  String Function()? value,
}) => QueryTrooper<String, ()>(
  namespace: namespace,
  fetch: (_) async => value?.call() ?? 'v',
  codec: TrooperCodec.string,
  config: TrooperConfig(storage: storage),
);

KeyedQueryTrooper<String, String, ()> _keyed(StorageBackend storage) =>
    KeyedQueryTrooper<String, String, ()>(
      namespace: 'contacts',
      fetch: (k, _) async => '$k@example.com',
      codec: TrooperCodec.string,
      config: TrooperConfig(storage: storage),
    );

void main() {
  group('L2 purge', () {
    test('get right after invalidate does not restore purged data', () async {
      final storage = InMemoryStorageBackend();
      var user = 'alice';
      final q = _query(storage, 'profile', value: () => user);
      expect(await q.get(()), 'alice');
      await pumpEventQueue();

      user = 'bob';
      q.invalidate();
      expect(await q.get(()), 'bob');
      await q.dispose();
    });

    test('invalidate keeps other namespaces and foreign keys', () async {
      final storage = InMemoryStorageBackend();
      await storage.write('app_setting', 'keep');
      final a = _query(storage, 'a');
      final ab = _query(storage, 'a:b');
      await a.get(());
      await ab.get(());
      await pumpEventQueue();

      a.invalidate();
      await pumpEventQueue();
      expect(await storage.getAllKeys(), {
        'app_setting',
        const QueryKey('a:b', ()).storageKey,
      });
      await a.dispose();
      await ab.dispose();
    });

    test(
      'invalidateKey purges that key from an earlier session only',
      () async {
        final storage = InMemoryStorageBackend();
        final first = _keyed(storage);
        await first['a'].get(());
        await first['b'].get(());
        await pumpEventQueue();
        await first.dispose();

        final second = _keyed(storage);
        second.invalidateKey('a');
        await pumpEventQueue();
        expect(await storage.getAllKeys(), {
          const QueryKey.keyed('contacts', parameter: (), key: 'b').storageKey,
        });
        await second.dispose();
      },
    );

    test('removeKey purges that key from an earlier session', () async {
      final storage = InMemoryStorageBackend();
      final first = _keyed(storage);
      await first['a'].get(());
      await pumpEventQueue();
      await first.dispose();

      final second = _keyed(storage);
      await second.removeKey('a');
      await pumpEventQueue();
      expect(await storage.getAllKeys(), isEmpty);
      await second.dispose();
    });

    test('a failing purge is reported as PersistenceErrorEvent', () async {
      final hub = TelemetryHub.isolated();
      final events = <PersistenceErrorEvent>[];
      hub.events
          .where((e) => e is PersistenceErrorEvent)
          .cast<PersistenceErrorEvent>()
          .listen(events.add);
      final q = QueryTrooper<String, ()>(
        namespace: 'failing',
        fetch: (_) async => 'v',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: _NoKeysStorage()),
        telemetry: hub,
      );
      q.invalidate();
      await pumpEventQueue();
      expect(events, hasLength(1));
      await q.dispose();
    });
  });
}

class _NoKeysStorage extends DelegatingStorageBackend {
  @override
  Future<Set<String>> getAllKeys() async => throw StateError('unsupported');
}
