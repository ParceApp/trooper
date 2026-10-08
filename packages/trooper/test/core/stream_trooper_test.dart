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
  });
}
