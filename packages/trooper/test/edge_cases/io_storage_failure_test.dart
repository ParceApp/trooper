import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';

void main() {
  group('Edge Case: Storage I/O Failure Resilience', () {
    test('handles disk write failures gracefully and retains in-memory data',
        () async {
      final storage = MockStorageBackend(failOnWrite: true);
      final events = <TrooperEvent>[];
      final hub = TelemetryHub.isolated();
      final sub = hub.events.listen(events.add);

      final query = QueryTrooper<String, ({int id})>(
        namespace: 'safe_items',
        fetch: (param) async => 'Data ${param.id}',
        codec: TrooperCodec.string,
        telemetry: hub,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(minutes: 5),
        ),
      );

      // Fetch should succeed in-memory even if persistent disk write throws FileSystemException
      final data = await query.get((id: 1));
      expect(data, 'Data 1');
      expect(query.currentData((id: 1)), 'Data 1');

      // Persistence error event should have been emitted
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.any((e) => e is PersistenceErrorEvent), isTrue);

      await sub.cancel();
      hub.dispose();
      query.dispose();
    });

    test('handles disk read failures gracefully and falls back to network fetch',
        () async {
      final storage = MockStorageBackend(failOnRead: true);

      final query = QueryTrooper<String, ()>(
        namespace: 'resilient_read',
        fetch: (_) async => 'Fresh from network',
        codec: TrooperCodec.string,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(minutes: 5),
        ),
      );

      final result = await query.get(const ());
      expect(result, 'Fresh from network');
      expect(query.currentData(const ()), 'Fresh from network');

      query.dispose();
    });

    test('LocalTrooper handles disk write failure, updates in-memory and emits PersistenceErrorEvent',
        () async {
      final storage = MockStorageBackend(failOnWrite: true);
      final events = <TrooperEvent>[];
      final hub = TelemetryHub.isolated();
      final sub = hub.events.listen(events.add);

      final local = LocalTrooper<String, ()>(
        namespace: 'local_storage_fail',
        initialValue: 'Default',
        codec: TrooperCodec.string,
        telemetry: hub,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(minutes: 5),
        ),
      );

      final updated = local.set('New Value', const ());
      expect(updated, 'New Value');
      expect(local.currentData(const ()), 'New Value');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.any((e) => e is PersistenceErrorEvent), isTrue);

      await sub.cancel();
      hub.dispose();
      local.dispose();
    });

    test('KeyedLocalTrooper handles disk write failure, updates in-memory and emits PersistenceErrorEvent',
        () async {
      final storage = MockStorageBackend(failOnWrite: true);
      final events = <TrooperEvent>[];
      final hub = TelemetryHub.isolated();
      final sub = hub.events.listen(events.add);

      final keyedLocal = KeyedLocalTrooper<int, String, ()>(
        namespace: 'keyed_local_storage_fail',
        initialValue: 'Default',
        codec: TrooperCodec.string,
        telemetry: hub,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(minutes: 5),
        ),
      );

      final updated = keyedLocal.setKey(10, 'Updated 10', const ());
      expect(updated, 'Updated 10');
      expect(keyedLocal.currentKeyData(10), 'Updated 10');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.any((e) => e is PersistenceErrorEvent), isTrue);

      await sub.cancel();
      hub.dispose();
      keyedLocal.dispose();
    });

    test('recovers gracefully when envelope payload cannot be decoded by codec',
        () async {
      final storage = InMemoryStorageBackend();
      // Write valid envelope with corrupt string payload that int codec cannot parse
      const key = QueryKey('corrupt_codec', ());
      final envelope = StorageEnvelope(
        payload: 'not_an_int',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await storage.write(key.storageKey, envelope.encode());

      final query = QueryTrooper<int, ()>(
        namespace: 'corrupt_codec',
        fetch: (_) async => 999,
        codec: TrooperCodec.integer,
        config: TrooperConfig(
          storage: storage,
          timeToLive: const Duration(minutes: 5),
        ),
      );

      // Decoding 'not_an_int' as int fails gracefully in hydrate, falling back to fetch
      final result = await query.get(const ());
      expect(result, 999);
      expect(query.currentData(const ()), 999);

      query.dispose();
    });
  });
}
