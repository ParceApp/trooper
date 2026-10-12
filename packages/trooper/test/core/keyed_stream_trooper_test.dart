import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';
import '../fixtures/mock_stream_source.dart';

void main() {
  group('KeyedStreamTrooper', () {
    late Map<String, MockStreamSource<String>> sources;
    late MockStorageBackend storage;

    setUp(() {
      sources = {};
      storage = MockStorageBackend();
    });

    tearDown(() async {
      for (final s in sources.values) {
        await s.close();
      }
    });

    MockStreamSource<String> getSource(String key) =>
        sources.putIfAbsent(key, () => MockStreamSource<String>());

    test('independent per-key connection and lifecycle', () async {
      final trooper = KeyedStreamTrooper<String, String, ()>(
        namespace: 'chat_rooms',
        streamFactory: (room, _, _) => getSource(room).stream,
        keepAlive: false,
      );

      final watcherA = trooper.watchKey('roomA', initialParameter: const ());
      final subA = watcherA.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(trooper.isConnectedKey('roomA'), isTrue);
      expect(trooper.isConnectedKey('roomB'), isFalse);

      final watcherB = trooper.watchKey('roomB', initialParameter: const ());
      final subB = watcherB.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(trooper.isConnectedKey('roomA'), isTrue);
      expect(trooper.isConnectedKey('roomB'), isTrue);

      await subA.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(trooper.isConnectedKey('roomA'), isFalse);
      expect(trooper.isConnectedKey('roomB'), isTrue);

      await subB.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(trooper.isConnectedKey('roomB'), isFalse);
      trooper.dispose();
    });

    test('getKey retrieves data from live stream or L2 storage envelope', () async {
      final trooper = KeyedStreamTrooper<String, String, ()>(
        namespace: 'market',
        streamFactory: (ticker, _, _) => getSource(ticker).stream,
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      final getFuture = trooper.getKey('AAPL', const ());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      getSource('AAPL').emit('\$220.50');
      final price = await getFuture;
      expect(price, '\$220.50');

      // Check L2 storage envelope
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(storage.writeCount, 1);

      // Hydrate from L2 storage via fresh instance
      final restored = KeyedStreamTrooper<String, String, ()>(
        namespace: 'market',
        streamFactory: (ticker, _, _) => getSource(ticker).stream,
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      final instant = await restored.getKey('AAPL', const ());
      expect(instant, '\$220.50');
      expect(restored.currentKeyData('AAPL'), '\$220.50');

      trooper.dispose();
      restored.dispose();
    });

    test('setKey, reconnectKey, removeKey and clearAll', () async {
      final trooper = KeyedStreamTrooper<String, String, ()>(
        namespace: 'channels',
        streamFactory: (ch, _, _) => getSource(ch).stream,
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );

      // setKey
      final setVal = trooper.setKey('general', 'welcome', const ());
      expect(setVal, 'welcome');
      expect(trooper.currentKeyData('general'), 'welcome');

      // connectKey
      await trooper.connectKey('general', const ());
      expect(trooper.isConnectedKey('general'), isTrue);

      // disconnectKey & connectKey
      await trooper.disconnectKey('general');
      expect(trooper.isConnectedKey('general'), isFalse);
      await trooper.connectKey('general', const ());
      expect(trooper.isConnectedKey('general'), isTrue);

      // removeKey
      await trooper.removeKey('general');
      expect(trooper.isConnectedKey('general'), isFalse);
      expect(trooper.currentKeyData('general'), isNull);

      // Add multiple and clearAll
      trooper.setKey('random', 'meme', const ());
      trooper.setKey('dev', 'pr merged', const ());
      expect(trooper.activeKeys, containsAll(['random', 'dev']));

      await trooper.clearAll();
      expect(trooper.activeKeys, isEmpty);

      trooper.dispose();
    });

    test('watchAll and watchKeys aggregates', () async {
      final trooper = KeyedStreamTrooper<String, String, ()>(
        namespace: 'feeds',
        streamFactory: (f, _, _) => getSource(f).stream,
      );

      final keySnapshots = <Set<String>>[];
      final allSnapshots = <Map<String, StatefulData<String>>>[];

      final keysSub = trooper.watchKeys().listen(keySnapshots.add);
      final allSub = trooper.watchAll().listen(allSnapshots.add);

      trooper.setKey('news', 'Breaking', const ());
      await Future<void>.delayed(Duration.zero);

      expect(keySnapshots.last, contains('news'));
      expect(allSnapshots.last['news']?.dataOrNull, 'Breaking');

      await keysSub.cancel();
      await allSub.cancel();
      trooper.dispose();
    });

    test('error propagation and recover in KeyedStreamTrooper', () async {
      var errorCaptured = false;
      final trooper = KeyedStreamTrooper<String, String, ()>(
        namespace: 'errors',
        streamFactory: (k, _, _) => getSource(k).stream,
        sideEffects: KeyedTrooperSideEffects(
          onError: (k, e, s, p) => errorCaptured = true,
        ),
      );

      final sub = trooper.watchKey('ch1', initialParameter: const ()).listen((_) {});
      await Future<void>.delayed(Duration.zero);

      getSource('ch1').emitError(StateError('Stream drop'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(trooper.stream.stateOf('ch1').isError, isTrue);
      expect(errorCaptured, isTrue);

      // recover, pause, resume
      trooper.recover();
      trooper.pause();
      trooper.resume();
      trooper.didChangeDependencies();

      await sub.cancel();
      trooper.dispose();
    });

    test('KeyedStreamTrooper.fromStream, operator [], and parameterless extension', () async {
      final controllers = <String, StreamController<String>>{};
      StreamController<String> getCtrl(String key) =>
          controllers.putIfAbsent(key, () => StreamController<String>.broadcast());

      var refreshHookCalled = false;
      var disconnectHookCalled = false;

      final trooper = KeyedStreamTrooper.fromStream<String, String>(
        namespace: 'from_stream_k',
        stream: (k) => getCtrl(k).stream,
        onRefresh: (_) => refreshHookCalled = true,
        onDisconnect: (_) => disconnectHookCalled = true,
      );

      // Bound accessor
      final accessor = trooper['room1'];
      final getFuture = accessor.get(const ());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      getCtrl('room1').add('Room 1 Payload');

      final val = await getFuture;
      expect(val, 'Room 1 Payload');

      // Refresh
      final refreshFuture = accessor.refresh(const ());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      getCtrl('room1').add('Room 1 Refreshed');
      final refreshedVal = await refreshFuture;
      expect(refreshedVal, 'Room 1 Refreshed');
      expect(refreshHookCalled, isTrue);

      // Parameterless extension
      await ParameterlessKeyedStreamTrooper(trooper).connectKey('room2');
      expect(trooper.isConnectedKey('room2'), isTrue);
      ParameterlessKeyedStreamTrooper(trooper).setKey('room2', 'Manual 2');
      expect(trooper.currentKeyData('room2'), 'Manual 2');

      final watcher = ParameterlessKeyedStreamTrooper(trooper).watchKey('room2', eager: false);
      expect(watcher.currentData, 'Manual 2');

      await trooper.disconnectKey('room1');
      expect(disconnectHookCalled, isTrue);

      await trooper.dispose();
      for (final c in controllers.values) {
        await c.close();
      }
    });

    test('KeyedStreamTrooper L2 storage persistence and hydration', () async {
      final storage = InMemoryStorageBackend();
      final codec = TrooperCodec.string;
      final controllers = <String, StreamController<String>>{};
      StreamController<String> getCtrl(String key) =>
          controllers.putIfAbsent(key, () => StreamController<String>.broadcast());

      final trooper1 = KeyedStreamTrooper<String, String, ()>(
        namespace: 'l2_stream_k',
        streamFactory: (k, _, _) => getCtrl(k).stream,
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      await trooper1.connectKey('k1', const ());
      getCtrl('k1').add('Frame K1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(trooper1.currentKeyData('k1'), 'Frame K1');
      await trooper1.dispose();

      // Instance 2 should hydrate immediately from storage on getKey
      final trooper2 = KeyedStreamTrooper<String, String, ()>(
        namespace: 'l2_stream_k',
        streamFactory: (k, _, _) => getCtrl(k).stream,
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      final hydrated = await trooper2.getKey('k1', const ());
      expect(hydrated, 'Frame K1');

      await trooper2.dispose();
      for (final c in controllers.values) {
        await c.close();
      }
    });
  });
}
