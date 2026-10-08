import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('KeyedStatefulStream Orchestration', () {
    test('tracks active keys, count, containsKey, and synchronous states', () {
      final keyed = KeyedStatefulStream<String, int>();

      expect(keyed.count, 0);
      expect(keyed.activeKeys, isEmpty);
      expect(keyed.containsKey('k1'), isFalse);
      expect(keyed.stateOf('k1'), isA<DataInitial<int>>());
      expect(keyed.dataOf('k1'), isNull);
      expect(keyed.hasListeners, isFalse);
      expect(keyed.hasKeyListeners('k1'), isFalse);

      keyed.emitData('k1', 100);
      expect(keyed.count, 1);
      expect(keyed.activeKeys, {'k1'});
      expect(keyed.containsKey('k1'), isTrue);
      expect(keyed.dataOf('k1'), 100);
      expect(keyed.currentDataMap, {'k1': 100});

      keyed.emitData('k2', 200);
      expect(keyed.count, 2);
      expect(keyed.activeKeys, {'k1', 'k2'});
      expect(keyed.currentDataMap, {'k1': 100, 'k2': 200});

      final allStates = keyed.currentStates;
      expect(allStates.keys, containsAll(['k1', 'k2']));
      expect(allStates['k1']!.dataOrNull, 100);
      expect(allStates['k2']!.dataOrNull, 200);

      keyed.close();
    });

    test('per-key streams emit all lifecycle transitions', () async {
      final keyed = KeyedStatefulStream<int, String>();
      final keyStream = keyed.streamOf(1);

      final events = <StatefulData<String>>[];
      final sub = keyStream.listen(events.add);

      expect(keyed.hasKeyListeners(1), isTrue);
      expect(keyed.hasListeners, isTrue);

      keyed.emitLoading(1, progress: 0.1);
      keyed.emitData(1, 'Item 1');
      keyed.emitRefreshing(1, 'Item 1', progress: 0.5);
      keyed.emitError(1, StateError('failed'), staleData: 'Item 1');
      keyed.emitInitial(1);

      await Future<void>.delayed(Duration.zero);

      expect(events.length, 6); // initial + 5 emissions
      expect(events[1], isA<DataLoading<String>>());
      expect(events[2], isA<DataLoaded<String>>());
      expect(events[3], isA<DataRefreshing<String>>());
      expect(events[4], isA<DataError<String>>());
      expect(events[5], isA<DataInitial<String>>());

      await sub.cancel();
      expect(keyed.hasKeyListeners(1), isFalse);
      await keyed.close();
    });

    test('watchAll reactively emits full snapshot on any key mutation', () async {
      final keyed = KeyedStatefulStream<String, int>();

      final snapshots = <Map<String, StatefulData<int>>>[];
      final sub = keyed.watchAll().listen(snapshots.add);

      await Future<void>.delayed(Duration.zero);
      expect(snapshots.length, 1); // Initial empty map

      keyed.emitData('user_1', 42);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.length, 2);
      expect(snapshots.last['user_1']?.dataOrNull, 42);

      keyed.emitData('user_2', 99);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.length, 3);
      expect(snapshots.last.length, 2);

      await sub.cancel();
      await keyed.close();
    });

    test('watchKeys emits set of keys on additions and removals', () async {
      final keyed = KeyedStatefulStream<String, String>();

      final keySets = <Set<String>>[];
      final sub = keyed.watchKeys().listen(keySets.add);

      await Future<void>.delayed(Duration.zero);
      expect(keySets.first, isEmpty);

      keyed.streamOf('a');
      await Future<void>.delayed(Duration.zero);
      expect(keySets.last, {'a'});

      keyed.emitData('b', 'value_b');
      await Future<void>.delayed(Duration.zero);
      expect(keySets.last, {'a', 'b'});

      await keyed.removeKey('a');
      await Future<void>.delayed(Duration.zero);
      expect(keySets.last, {'b'});

      await sub.cancel();
      await keyed.close();
    });

    test('clearAll and close cleanly tear down all child controllers', () async {
      final keyed = KeyedStatefulStream<int, String>();
      keyed.emitData(1, 'One');
      keyed.emitData(2, 'Two');

      expect(keyed.count, 2);

      await keyed.clearAll();
      expect(keyed.count, 0);
      expect(keyed.activeKeys, isEmpty);

      keyed.emitData(3, 'Three');
      expect(keyed.count, 1);

      await keyed.dispose();
      expect(keyed.isClosed, isTrue);

      // Subsequent emissions on closed manager are safely dropped
      keyed.emitData(3, 'After close');
    });
  });
}
