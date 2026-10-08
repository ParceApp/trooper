import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';
import '../fixtures/mock_stream_source.dart';

void main() {
  group('StreamTrooper', () {
    late MockStreamSource<String> source;
    late MockStorageBackend storage;

    setUp(() {
      source = MockStreamSource<String>();
      storage = MockStorageBackend();
    });

    tearDown(() async {
      await source.close();
    });

    test('automatic lifecycle with keepAlive false connects and disconnects on demand',
        () async {
      var connects = 0;
      var disconnects = 0;

      final trooper = StreamTrooper<String, ()>(
        namespace: 'ticker',
        streamFactory: (_, _) => source.stream,
        onConnect: (_, _) => connects++,
        onDisconnect: () => disconnects++,
        keepAlive: false,
      );

      expect(trooper.isConnected, isFalse);

      final watcher = trooper.watch(const ());
      final sub = watcher.listen((_) {});

      // Allow microtask to connect
      await Future<void>.delayed(Duration.zero);
      expect(trooper.isConnected, isTrue);
      expect(connects, 1);

      // Cancel subscription
      await sub.cancel();
      // Allow async disconnect
      await Future<void>.delayed(Duration.zero);

      expect(trooper.isConnected, isFalse);
      expect(disconnects, 1);

      trooper.dispose();
    });

    test('keepAlive true retains upstream subscription when listeners drop to 0',
        () async {
      final trooper = StreamTrooper<String, ()>(
        namespace: 'persistent_stream',
        streamFactory: (_, _) => source.stream,
        keepAlive: true,
      );

      final watcher = trooper.watch(const ());
      final sub = watcher.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(trooper.isConnected, isTrue);

      await sub.cancel();
      await Future<void>.delayed(Duration.zero);

      // Connection should still be active
      expect(trooper.isConnected, isTrue);

      await trooper.disconnect();
      expect(trooper.isConnected, isFalse);
      trooper.dispose();
    });

    test('get awaits next upstream stream frame when cache misses', () async {
      final trooper = StreamTrooper<String, ()>(
        namespace: 'notifications',
        streamFactory: (_, _) => source.stream,
      );

      final getFuture = trooper.get(const ());

      // Emit data into upstream source
      await Future<void>.delayed(const Duration(milliseconds: 10));
      source.emit('Alert Message');

      final result = await getFuture;
      expect(result, 'Alert Message');
      expect(trooper.currentData(const ()), 'Alert Message');

      trooper.dispose();
    });

    test('persists stream frames to L2 with StorageEnvelope and supports instant hydration',
        () async {
      final trooper = StreamTrooper<String, ()>(
        namespace: 'feed',
        streamFactory: (_, _) => source.stream,
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      final watcher = trooper.watch(const ());
      final sub = watcher.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      source.emit('Item #1');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(storage.writeCount, 1);
      final rawEnvelope = await storage.read(QueryKey(trooper.namespace, const ()).storageKey);
      expect(rawEnvelope, isNotNull);
      final envelope = StorageEnvelope.tryDecode(rawEnvelope!);
      expect(envelope, isNotNull);
      expect(envelope!.payload, 'Item #1');

      await sub.cancel();
      await trooper.disconnect();

      // Fresh stream instance should instant-hydrate from L2 in get()
      final restoredTrooper = StreamTrooper<String, ()>(
        namespace: 'feed',
        streamFactory: (_, _) => source.stream,
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(hours: 1),
        ),
      );

      final instant = await restoredTrooper.get(const ());
      expect(instant, 'Item #1');
      expect(restoredTrooper.currentData(const ()), 'Item #1');

      trooper.dispose();
      restoredTrooper.dispose();
    });

    test('set updates in-memory state and persists to storage', () async {
      final trooper = StreamTrooper<String, ()>(
        namespace: 'chat_state',
        streamFactory: (_, _) => source.stream,
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );

      final returned = trooper.set('pinned_message', const ());
      expect(returned, 'pinned_message');
      expect(trooper.currentData(const ()), 'pinned_message');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(storage.writeCount, 1);

      trooper.dispose();
    });

    test('error propagation and recover on StreamTrooper', () async {
      var errorCaptured = false;
      final trooper = StreamTrooper<String, ()>(
        namespace: 'crypto_feed',
        streamFactory: (_, _) => source.stream,
        sideEffects: TrooperSideEffects(
          onError: (e, s, p) => errorCaptured = true,
        ),
      );

      final sub = trooper.watch(const ()).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(trooper.isConnected, isTrue);

      source.emitError(StateError('Socket disconnect'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(trooper.stream.isError, isTrue);
      expect(errorCaptured, isTrue);

      // Reconnect / recover
      trooper.recover();
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      trooper.dispose();
    });

    test('pause, resume, and didChangeDependencies on StreamTrooper', () async {
      final trooper = StreamTrooper<String, ()>(
        namespace: 'lifecycle_feed',
        streamFactory: (_, _) => source.stream,
      );

      final sub = trooper.watch(const ()).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(trooper.isConnected, isTrue);

      trooper.pause();
      trooper.resume();
      await sub.cancel();
      trooper.dispose();
    });

    test('StreamTrooper.fromStream and autoConnect', () async {
      final s = StreamController<String>.broadcast();
      final trooper = StreamTrooper.fromStream<String>(
        namespace: 'from_stream_ns',
        stream: () => s.stream,
        autoConnect: true,
      );

      expect(trooper.isConnected, isTrue);

      s.add('Hello from factory');
      await Future<void>.delayed(Duration.zero);
      expect(trooper.currentData(const ()), 'Hello from factory');

      await trooper.disconnect();
      expect(trooper.isConnected, isFalse);

      await ParameterlessStreamTrooper(trooper).connect();
      expect(trooper.isConnected, isTrue);

      await trooper.dispose();
      await s.close();
    });

    test('StreamTrooper query-like get and refresh semantics', () async {
      var refreshed = false;
      var disconnected = false;
      final s = StreamController<String>.broadcast();

      final trooper = StreamTrooper<String, ()>(
        namespace: 'query_stream',
        streamFactory: (_, _) => s.stream,
        onRefresh: (_) => refreshed = true,
        onDisconnect: () => disconnected = true,
      );

      // get() should connect, wait for first loaded event, and return the value
      final getFuture = trooper.get(const ());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      s.add('First Frame');

      final val = await getFuture;
      expect(val, 'First Frame');

      // Now refresh() invokes onRefresh hook
      final refreshFuture = trooper.refresh(const ());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      s.add('Second Frame');

      final refreshedVal = await refreshFuture;
      expect(refreshedVal, 'Second Frame');
      expect(refreshed, isTrue);

      await trooper.dispose();
      expect(disconnected, isTrue);
      await s.close();
    });

    test('StreamTrooper L2 storage persistence and hydration', () async {
      final storage = InMemoryStorageBackend();
      final codec = TrooperCodec.string;
      final s = StreamController<String>.broadcast();

      final trooper1 = StreamTrooper<String, ()>(
        namespace: 'persisted_stream',
        streamFactory: (_, _) => s.stream,
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      await trooper1.connect(const ());
      s.add('Frame 1');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(trooper1.currentData(const ()), 'Frame 1');
      await trooper1.dispose();

      // Instance 2 should hydrate immediately from storage on get or connect
      final trooper2 = StreamTrooper<String, ()>(
        namespace: 'persisted_stream',
        streamFactory: (_, _) => s.stream,
        codec: codec,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(milliseconds: 50),
          stalePolicy: StalePolicy.keepStaleWhileRevalidate,
        ),
      );

      final hydrated = await trooper2.get(const ());
      expect(hydrated, 'Frame 1');

      await trooper2.dispose();
      await s.close();
    });
  });
}
