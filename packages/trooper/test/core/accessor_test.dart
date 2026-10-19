import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';
import 'package:trooper/src/core/keyed_trooper_accessor.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';

void main() {
  group('Accessor & ParameterlessAccessor', () {
    test(
      'trooper.accessor provides valid Accessor and ParameterlessAccessor extensions',
      () async {
        final query = QueryTrooper<String, ()>(
          namespace: 'app_title',
          fetch: (_) async => 'My Application',
        );

        final Accessor<String, ()> accessor = query.accessor;

        // Accessor current() and currentData() methods
        expect(accessor.current(), isA<DataInitial<String>>());
        expect(accessor.currentData(), isNull);

        // Trigger background via extension
        ParameterlessAccessor(accessor).trigger();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(accessor.currentData(), 'My Application');
        expect(accessor.current(), isA<DataLoaded<String>>());

        // Get via extension
        final data = await ParameterlessAccessor(accessor).get();
        expect(data, 'My Application');

        // Refresh via extension
        final refreshed = await ParameterlessAccessor(accessor).refresh();
        expect(refreshed, 'My Application');

        // Watch via extension
        final watcher = ParameterlessAccessor(accessor).watch();
        expect(watcher.currentData, 'My Application');

        // Standard Accessor methods
        expect(accessor.current(), isA<DataLoaded<String>>());
        expect(accessor.currentData(), 'My Application');

        // Invalidate
        accessor.invalidate();
        expect(accessor.current(), isA<DataInitial<String>>());

        query.dispose();
      },
    );
  });

  group('KeyedAccessor & KeyedTrooperAccessor', () {
    test(
      'keyedTrooper.accessor provides full KeyedAccessor functionality',
      () async {
        final keyedQuery = KeyedQueryTrooper<int, String, ()>(
          namespace: 'users',
          fetch: (id, _) async => 'User $id',
        );

        final KeyedAccessor<int, String, ()> accessor = keyedQuery.accessor;

        expect(accessor.count, 0);
        expect(accessor.activeKeys, isEmpty);
        expect(accessor.currentDataMap, isEmpty);
        expect(accessor.currentStates, isEmpty);
        expect(accessor.current(), isA<DataInitial<Map<int, String>>>());
        expect(accessor.currentData(), isNull);

        // Read via single key accessor operator []
        final user1 = await accessor[1].get(const ());
        expect(user1, 'User 1');

        final user2 = await accessor[2].get(const ());
        expect(user2, 'User 2');

        expect(accessor.count, 2);
        expect(accessor.activeKeys, {1, 2});
        expect(accessor.currentDataMap, {1: 'User 1', 2: 'User 2'});
        expect(accessor.currentData(), {1: 'User 1', 2: 'User 2'});
        expect(accessor.current(), isA<DataLoaded<Map<int, String>>>());

        // Collection-level read & refresh
        // Invalidate key 1
        accessor.invalidateKey(1);
        expect(keyedQuery.currentKey(1), isA<DataInitial<String>>());

        // Watch entire collection contains key 2
        final collectionStream = accessor.watch();
        expect(
          collectionStream.currentState.dataOrNull,
          containsPair(2, 'User 2'),
        );

        // Collection-level read
        final collectionData = await accessor.get(const ());
        expect(collectionData, {2: 'User 2'});

        // Invalidate collection via refresh
        final refreshedCollection = await accessor.refresh(const ());
        expect(refreshedCollection, isEmpty);
        expect(accessor.currentDataMap, isEmpty);

        // Invalidate collection
        accessor.invalidate();
        expect(accessor.currentDataMap, isEmpty);

        keyedQuery.dispose();
      },
    );

    test('KeyedTrooperAccessor custom read and refresh handlers', () async {
      final stream = KeyedStatefulStream<String, int>();
      var refreshed = false;

      final customAccessor = KeyedTrooperAccessor<String, int, ()>(
        stream: stream,
        accessorFactory: (k) => throw UnimplementedError(),
        onInvalidate: () {},
        onRead: () async => {'custom': 999},
        onRefresh: () async {
          refreshed = true;
          return {'refreshed': 1000};
        },
      );

      final readData = await customAccessor.get(const ());
      expect(readData, {'custom': 999});

      final refreshedData = await customAccessor.get(
        const (),
        forceRefresh: true,
      );
      expect(refreshedData, {'refreshed': 1000});
      expect(refreshed, isTrue);

      final manualRefreshed = await customAccessor.refresh(const ());
      expect(manualRefreshed, {'refreshed': 1000});

      customAccessor.trigger(const ());
      await Future<void>.delayed(Duration.zero);

      await stream.close();
    });
  });
}
