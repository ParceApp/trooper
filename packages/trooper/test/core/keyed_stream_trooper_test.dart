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

      final watcherA = trooper.watchKey('roomA', const ());
      final subA = watcherA.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(trooper.isConnectedKey('roomA'), isTrue);
      expect(trooper.isConnectedKey('roomB'), isFalse);

      final watcherB = trooper.watchKey('roomB', const ());
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
  });
}
