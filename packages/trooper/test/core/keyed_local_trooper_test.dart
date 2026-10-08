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
  });
}
