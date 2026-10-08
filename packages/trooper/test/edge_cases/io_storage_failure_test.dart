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

      final query = TrooperQuery<String, ({int id})>(
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

      final query = TrooperQuery<String, ()>(
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
  });
}
