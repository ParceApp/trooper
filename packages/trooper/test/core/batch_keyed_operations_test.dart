import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('KeyedLocalTrooper Batch Operations', () {
    test(
      'setAll, updateAll, resetKeys, and getAll mutate and read multiple keys',
      () async {
        final trooper = KeyedLocalTrooper<String, int, ()>(
          namespace: 'batch_local',
          initialValue: 0,
        );

        // setAll
        final setRes = trooper.setAll({'a': 10, 'b': 20, 'c': 30}, const ());
        expect(setRes, {'a': 10, 'b': 20, 'c': 30});
        expect(trooper.currentDataMap, {'a': 10, 'b': 20, 'c': 30});

        // updateAll
        final updateRes = trooper.updateAll({
          'a': (prev) => prev + 5,
          'b': (prev) => prev * 2,
        }, const ());
        expect(updateRes, {'a': 15, 'b': 40});
        expect(trooper.currentKeyData('a'), 15);
        expect(trooper.currentKeyData('b'), 40);

        // getAll
        final allRes = await trooper.getAll(['a', 'c'], const ());
        expect(allRes, {'a': 15, 'c': 30});

        // resetKeys
        final resetRes = trooper.resetKeys(['a', 'b'], const ());
        expect(resetRes, {'a': 0, 'b': 0});
        expect(trooper.currentKeyData('a'), 0);
        expect(trooper.currentKeyData('b'), 0);
        expect(trooper.currentKeyData('c'), 30);

        trooper.dispose();
      },
    );

    test(
      'setAllAsync and resetKeysAsync await persistence across multiple keys',
      () async {
        final storage = InMemoryStorageBackend();
        final trooper = KeyedLocalTrooper<String, String, ()>(
          namespace: 'async_batch_local',
          initialValue: 'init',
          codec: TrooperCodec.string,
          config: TrooperConfig(storage: storage),
        );

        final entries = {'user1': 'Alice', 'user2': 'Bob'};
        await trooper.setAllAsync(entries, const ());

        expect(trooper.currentKeyData('user1'), 'Alice');
        expect(trooper.currentKeyData('user2'), 'Bob');

        // Check stored in backend
        final k1 = QueryKey.keyed(
          'async_batch_local',
          key: 'user1',
          parameter: const (),
        );
        final k2 = QueryKey.keyed(
          'async_batch_local',
          key: 'user2',
          parameter: const (),
        );
        expect(await storage.containsKey(k1.storageKey), isTrue);
        expect(await storage.containsKey(k2.storageKey), isTrue);

        // resetKeysAsync
        await trooper.resetKeysAsync(['user1', 'user2'], const ());
        expect(trooper.currentKeyData('user1'), 'init');
        expect(trooper.currentKeyData('user2'), 'init');
        expect(await storage.containsKey(k1.storageKey), isFalse);
        expect(await storage.containsKey(k2.storageKey), isFalse);

        trooper.dispose();
      },
    );

    test('ParameterlessKeyedLocalTrooper batch extension methods', () async {
      final trooper = KeyedLocalTrooper<String, int, ()>(
        namespace: 'paramless_batch_local',
        initialValue: -1,
      );

      ParameterlessKeyedLocalTrooper(trooper).setAll({'x': 100, 'y': 200});
      expect(await ParameterlessKeyedLocalTrooper(trooper).getAll(['x', 'y']), {
        'x': 100,
        'y': 200,
      });

      ParameterlessKeyedLocalTrooper(
        trooper,
      ).updateAll({'x': (v) => v + 1, 'y': (v) => v + 2});
      expect(await ParameterlessKeyedLocalTrooper(trooper).getAll(['x', 'y']), {
        'x': 101,
        'y': 202,
      });

      ParameterlessKeyedLocalTrooper(trooper).resetKeys(['x']);
      expect(trooper.currentKeyData('x'), -1);
      expect(trooper.currentKeyData('y'), 202);

      await ParameterlessKeyedLocalTrooper(trooper).setAllAsync({'x': 500});
      expect(trooper.currentKeyData('x'), 500);

      await ParameterlessKeyedLocalTrooper(trooper).resetKeysAsync(['x', 'y']);
      expect(trooper.currentKeyData('x'), -1);
      expect(trooper.currentKeyData('y'), -1);

      trooper.dispose();
    });
  });

  group('KeyedQueryTrooper Batch Operations', () {
    test('getAll and refreshKeys fetch multiple keys concurrently', () async {
      var fetchCounts = <String, int>{};
      final query = KeyedQueryTrooper<String, String, ()>(
        namespace: 'batch_query',
        fetch: (key, param) async {
          fetchCounts[key] = (fetchCounts[key] ?? 0) + 1;
          return 'Value for $key (#${fetchCounts[key]})';
        },
      );

      final results = await query.getAll(['k1', 'k2', 'k3'], const ());
      expect(results, {
        'k1': 'Value for k1 (#1)',
        'k2': 'Value for k2 (#1)',
        'k3': 'Value for k3 (#1)',
      });

      // From cache
      final cachedResults = await query.getAll(['k1', 'k2'], const ());
      expect(cachedResults, {
        'k1': 'Value for k1 (#1)',
        'k2': 'Value for k2 (#1)',
      });
      expect(fetchCounts['k1'], 1);

      // refreshKeys forces refresh
      final refreshed = await query.refreshKeys(['k1', 'k2'], const ());
      expect(refreshed, {'k1': 'Value for k1 (#2)', 'k2': 'Value for k2 (#2)'});
      expect(fetchCounts['k1'], 2);

      // triggerKeys
      query.triggerKeys(['k1', 'k2'], const ());
      // Invalidation & removal
      query.invalidateKeys(['k1', 'k2']);
      expect(query.stream.stateOf('k1'), isA<DataInitial<String>>());
      expect(query.stream.stateOf('k2'), isA<DataInitial<String>>());

      await query.removeKeys(['k1', 'k2', 'k3']);
      expect(query.stream.activeKeys, isEmpty);

      await query.dispose();
    });

    test('ParameterlessKeyedQueryTrooper batch extension methods', () async {
      final query = KeyedQueryTrooper<String, int, ()>(
        namespace: 'paramless_batch_query',
        fetch: (key, param) async => key.length,
      );

      final res = await ParameterlessKeyedQueryTrooper(
        query,
      ).getAll(['apple', 'banana']);
      expect(res, {'apple': 5, 'banana': 6});

      final refreshed = await ParameterlessKeyedQueryTrooper(
        query,
      ).refreshKeys(['apple']);
      expect(refreshed, {'apple': 5});

      ParameterlessKeyedQueryTrooper(query).triggerKeys(['banana']);
      await query.dispose();
    });
  });

  group('KeyedStreamTrooper Batch Operations', () {
    test(
      'connectKeys, disconnectKeys, getAll, refreshKeys, and triggerKeys',
      () async {
        final controllers = <String, StreamController<int>>{};
        StreamController<int> getController(String key) => controllers
            .putIfAbsent(key, () => StreamController<int>.broadcast());

        final streamTrooper = KeyedStreamTrooper<String, int, ()>(
          namespace: 'batch_stream',
          streamFactory: (key, param, cancelToken) => getController(key).stream,
        );

        // Connect multiple keys concurrently
        final connectFuture = streamTrooper.connectKeys(['s1', 's2'], const ());
        expect(streamTrooper.isConnectedKey('s1'), isTrue);
        expect(streamTrooper.isConnectedKey('s2'), isTrue);

        // Emit data on each stream
        getController('s1').add(10);
        getController('s2').add(20);

        await connectFuture;
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(streamTrooper.currentKeyData('s1'), 10);
        expect(streamTrooper.currentKeyData('s2'), 20);

        // getAll returns current cached or waited values
        final all = await streamTrooper.getAll(['s1', 's2'], const ());
        expect(all, {'s1': 10, 's2': 20});

        // Disconnect keys
        await streamTrooper.disconnectKeys(['s1', 's2']);
        expect(streamTrooper.isConnectedKey('s1'), isFalse);
        expect(streamTrooper.isConnectedKey('s2'), isFalse);

        await streamTrooper.dispose();
        for (final c in controllers.values) {
          await c.close();
        }
      },
    );

    test('ParameterlessKeyedStreamTrooper batch extension methods', () async {
      final controller = StreamController<String>.broadcast();
      final streamTrooper = KeyedStreamTrooper<String, String, ()>(
        namespace: 'paramless_batch_stream',
        streamFactory: (key, param, token) => controller.stream,
      );

      await ParameterlessKeyedStreamTrooper(streamTrooper).connectKeys(['c1']);
      expect(streamTrooper.isConnectedKey('c1'), isTrue);

      controller.add('hello');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final res = await ParameterlessKeyedStreamTrooper(
        streamTrooper,
      ).getAll(['c1']);
      expect(res, {'c1': 'hello'});

      await ParameterlessKeyedStreamTrooper(
        streamTrooper,
      ).disconnectKeys(['c1']);
      expect(streamTrooper.isConnectedKey('c1'), isFalse);

      await streamTrooper.dispose();
      await controller.close();
    });
  });

  group('KeyedAccessor Batch Operations', () {
    test('KeyedAccessor facade delegates batch calls correctly', () async {
      final query = KeyedQueryTrooper<String, int, ()>(
        namespace: 'accessor_batch',
        fetch: (key, param) async => key.hashCode,
      );

      final KeyedAccessor<String, int, ()> accessor = query.accessor;

      final batch = await accessor.getAll(['k1', 'k2'], const ());
      expect(batch.keys, containsAll(['k1', 'k2']));

      accessor.triggerKeys(['k1', 'k2'], const ());
      accessor.invalidateKeys(['k1', 'k2']);
      expect(accessor.currentStates['k1'], isA<DataInitial<int>>());

      // ParameterlessKeyedAccessor
      final extBatch = await ParameterlessKeyedAccessor(
        accessor,
      ).getAll(['k1']);
      expect(extBatch.containsKey('k1'), isTrue);

      ParameterlessKeyedAccessor(accessor).invalidateKeys(['k1']);
      expect(accessor.currentStates['k1'], isA<DataInitial<int>>());

      await query.dispose();
    });
  });
}
