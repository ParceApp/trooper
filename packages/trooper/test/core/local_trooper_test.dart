import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';

void main() {
  group('LocalTrooper', () {
    late MockStorageBackend storage;

    setUp(() {
      storage = MockStorageBackend();
    });

    test('synchronous set and update mutate in-memory state and emit to stream',
        () async {
      final trooper = LocalTrooper<int, ()>(
        namespace: 'counter',
        initialValue: 0,
      );

      final values = <int>[];
      final sub = trooper.stream.dataStream.listen(values.add);

      expect(trooper.currentData(const ()), 0);

      trooper.set(5, const ());
      expect(trooper.currentData(const ()), 5);

      trooper.update((prev) => prev + 10, const ());
      expect(trooper.currentData(const ()), 15);

      trooper.reset(const ());
      expect(trooper.currentData(const ()), 0);

      await Future<void>.delayed(Duration.zero);
      expect(values, [0, 5, 15, 0]);

      await sub.cancel();
      trooper.dispose();
    });

    test('persists to L2 with StorageEnvelope and restores on hydration',
        () async {
      final trooper = LocalTrooper<String, ()>(
        namespace: 'theme',
        initialValue: 'light',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );

      trooper.set('dark', const ());

      // Allow async write to storage
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(storage.writeCount, 1);

      // Verify envelope
      final raw = await storage.read(QueryKey(trooper.namespace, const ()).storageKey);
      expect(raw, isNotNull);
      final envelope = StorageEnvelope.tryDecode(raw!);
      expect(envelope, isNotNull);
      expect(envelope!.payload, 'dark');

      // Hydrate via fresh instance
      final restored = LocalTrooper<String, ()>(
        namespace: 'theme',
        initialValue: 'light',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: storage),
      );

      final loaded = await restored.get(const ());
      expect(loaded, 'dark');
      expect(restored.currentData(const ()), 'dark');

      trooper.dispose();
      restored.dispose();
    });
  });
}
