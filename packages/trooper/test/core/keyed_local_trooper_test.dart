import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';

void main() {
  group('KeyedLocalTrooper', () {
    late MockStorageBackend storage;

    setUp(() {
      storage = MockStorageBackend();
    });

    test('synchronous setKey and updateKey mutate per-key state', () async {
      final trooper = KeyedLocalTrooper<String, String, ()>(
        namespace: 'drafts',
        initialValue: '',
      );

      trooper.setKey('doc1', 'Hello World', const ());
      expect(trooper.currentKeyData('doc1'), 'Hello World');

      trooper.updateKey('doc1', (prev) => '$prev!', const ());
      expect(trooper.currentKeyData('doc1'), 'Hello World!');

      trooper.resetKey('doc1', const ());
      expect(trooper.currentKeyData('doc1'), '');

      trooper.dispose();
    });

    test('persists per-key to L2 with StorageEnvelope and restores on hydration',
        () async {
      final trooper = KeyedLocalTrooper<int, int, ()>(
        namespace: 'settings',
        initialValue: 0,
        codec: TrooperCodec.integer,
        config: TrooperConfig(storage: storage),
      );

      trooper.setKey(99, 42, const ());

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(storage.writeCount, 1);

      // Hydrate via fresh instance
      final restored = KeyedLocalTrooper<int, int, ()>(
        namespace: 'settings',
        initialValue: 0,
        codec: TrooperCodec.integer,
        config: TrooperConfig(storage: storage),
      );

      final val = await restored.getKey(99, const ());
      expect(val, 42);
      expect(restored.currentKeyData(99), 42);

      trooper.dispose();
      restored.dispose();
    });

    test('removeKey cleans up in-memory and persistent storage', () async {
      final trooper = KeyedLocalTrooper<String, String, ()>(
        namespace: 'tags',
        initialValue: 'none',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );

      trooper.setKey('t1', 'urgent', const ());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await trooper.removeKey('t1');
      expect(trooper.activeKeys.contains('t1'), isFalse);
      expect(storage.deleteCount, 1);

      trooper.dispose();
    });

    test('clearAll, watchKey, watchAll and lifecycle in KeyedLocalTrooper', () async {
      final trooper = KeyedLocalTrooper<String, String, ()>(
        namespace: 'workspace',
        initialValue: 'default',
      );

      final keyWatcher = trooper.watchKey('k1');
      final allWatcher = trooper.watchAll();
      final keysWatcher = trooper.watchKeys();

      final keyStates = <StatefulData<String>>[];
      final allStates = <Map<String, StatefulData<String>>>[];
      final activeSets = <Set<String>>[];

      final sub1 = keyWatcher.listen(keyStates.add);
      final sub2 = allWatcher.listen(allStates.add);
      final sub3 = keysWatcher.listen(activeSets.add);

      trooper.setKey('k1', 'val1', const ());
      trooper.setKey('k2', 'val2', const ());
      await Future<void>.delayed(Duration.zero);

      expect(trooper.count, 2);
      expect(activeSets.last, containsAll(['k1', 'k2']));
      expect(allStates.last['k1']?.dataOrNull, 'val1');

      await trooper.clearAll();
      expect(trooper.count, 0);

      trooper.pause();
      trooper.resume();
      trooper.recover();
      trooper.didChangeDependencies();

      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
      trooper.dispose();
    });

    test('operator [] returns KeyedLocalBoundAccessor with mutations and inspection', () async {
      final trooper = KeyedLocalTrooper<String, int, ()>.builder(
        namespace: 'bound_local',
        initialValueFactory: (key) => key.length,
      );

      final accessor = trooper['hello'];
      expect(accessor.currentData(const ()), 5);
      expect(accessor.current(const ()), isA<DataLoaded<int>>());
      expect(trooper.initialValueOf('hello'), 5);

      final data = await accessor.get(const ());
      expect(data, 5);

      final refreshed = await accessor.refresh(const ());
      expect(refreshed, 5);

      accessor.trigger(const ());
      accessor.invalidate();

      final watcher = accessor.watch();
      expect(watcher.currentData, isNull);

      trooper.dispose();
    });

    test('ParameterlessKeyedLocalTrooper extension methods', () async {
      final trooper = KeyedLocalTrooper<String, String, ()>(
        namespace: 'paramless_local',
        initialValue: 'init',
      );

      expect(
        ParameterlessKeyedLocalTrooper(trooper).setKey('k1', 'new_val'),
        'new_val',
      );
      expect(
        ParameterlessKeyedLocalTrooper(trooper).updateKey('k1', (curr) => '$curr!'),
        'new_val!',
      );
      expect(
        await ParameterlessKeyedLocalTrooper(trooper).getKey('k1'),
        'new_val!',
      );
      expect(
        await ParameterlessKeyedLocalTrooper(trooper).refreshKey('k1'),
        'new_val!',
      );

      ParameterlessKeyedLocalTrooper(trooper).triggerKey('k1');
      final watcher = ParameterlessKeyedLocalTrooper(trooper).watchKey('k1', eager: false);
      expect(watcher.currentData, 'new_val!');

      expect(ParameterlessKeyedLocalTrooper(trooper).resetKey('k1'), 'init');
      expect(trooper.currentKeyData('k1'), 'init');

      ParameterlessKeyedLocalTrooper(trooper).setKey('k1', 'v1');
      ParameterlessKeyedLocalTrooper(trooper).setKey('k2', 'v2');
      trooper.resetAll();
      expect(trooper.currentKeyData('k1'), 'init');
      expect(trooper.currentKeyData('k2'), 'init');

      trooper.dispose();
    });

    test('L2 storage persistence and hydration in KeyedLocalTrooper', () async {
      final storage = InMemoryStorageBackend();
      final codec = TrooperCodec.string;

      final trooper1 = KeyedLocalTrooper<String, String, ()>(
        namespace: 'l2_local',
        initialValue: 'fresh_init',
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
        ),
      );

      expect(trooper1.isHydratedKey('itemA'), isFalse);
      trooper1.setKey('itemA', 'persisted_val', const ());
      await Future<void>.delayed(Duration.zero);
      trooper1.dispose();

      // Second instance should hydrate from storage
      final trooper2 = KeyedLocalTrooper<String, String, ()>(
        namespace: 'l2_local',
        initialValue: 'fresh_init',
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
        ),
      );

      final hydrated = await trooper2.getKey('itemA', const ());
      expect(hydrated, 'persisted_val');
      expect(trooper2.isHydratedKey('itemA'), isTrue);

      // Expired envelope handling
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final trooper3 = KeyedLocalTrooper<String, String, ()>(
        namespace: 'l2_local',
        initialValue: 'fresh_init',
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
        ),
      );

      final afterExpiry = await trooper3.getKey('itemA', const ());
      // Expired L2 storage entry deleted and returns initialValue
      expect(afterExpiry, 'fresh_init');

      trooper2.dispose();
      trooper3.dispose();
    });
  });
}
