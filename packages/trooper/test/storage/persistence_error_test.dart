import 'dart:async';

import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _FailingStorage extends InMemoryStorageBackend {
  bool failWrite = false;
  bool failDelete = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('disk full');
    return super.write(key, value);
  }

  @override
  Future<String?> delete(String key) async {
    if (failDelete) throw StateError('disk locked');
    return super.delete(key);
  }
}

void main() {
  late TelemetryHub hub;
  late List<PersistenceErrorEvent> events;
  late _FailingStorage storage;

  setUp(() {
    hub = TelemetryHub.isolated();
    events = [];
    hub.events.listen((e) {
      if (e is PersistenceErrorEvent) events.add(e);
    });
    storage = _FailingStorage();
  });

  group('QueryTrooper L2 read', () {
    const key = QueryKey('pe_q', ());

    QueryTrooper<String, ()> query() => QueryTrooper<String, ()>(
      namespace: 'pe_q',
      fetch: (_) async => 'fetched',
      codec: TrooperCodec.string,
      config: TrooperConfig(storage: storage),
      telemetry: hub,
    );

    test('unreadable entry is reported and deleted', () async {
      await storage.write(key.storageKey, 'not json');
      final q = query();

      expect(await q.get(()), 'fetched');
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.error, isA<TrooperStorageException>());
      expect(
        StorageEnvelope.tryDecode((await storage.read(key.storageKey))!),
        isNotNull,
        reason: 'unreadable entry replaced by the fetched one',
      );
      await q.dispose();
    });

    test('failed delete of an unreadable entry is reported', () async {
      await storage.write(key.storageKey, 'not json');
      storage.failDelete = true;
      final q = query();

      await q.get(());
      await pumpEventQueue();

      expect(
        events.map((e) => e.error),
        contains(
          isA<StateError>().having((e) => e.message, 'm', 'disk locked'),
        ),
      );
      await q.dispose();
    });
  });

  test('StreamTrooper reports a failed L2 write', () async {
    final source = StreamController<String>.broadcast();
    final trooper = StreamTrooper<String, ()>(
      namespace: 'pe_s',
      streamFactory: (_, _) => source.stream,
      codec: TrooperCodec.string,
      config: TrooperConfig(storage: storage),
      telemetry: hub,
    );
    storage.failWrite = true;
    final sub = trooper.watch(initialParameter: const ()).listen((_) {});
    await pumpEventQueue();

    source.add('frame');
    await pumpEventQueue();

    expect(
      events.map((e) => e.error),
      contains(isA<StateError>().having((e) => e.message, 'm', 'disk full')),
    );
    await sub.cancel();
    await trooper.dispose();
    await source.close();
  });

  test('KeyedStreamTrooper reports a failed L2 write', () async {
    final source = StreamController<String>.broadcast();
    final trooper = KeyedStreamTrooper<String, String, ()>(
      namespace: 'pe_ks',
      streamFactory: (_, _, _) => source.stream,
      codec: TrooperCodec.string,
      config: TrooperConfig(storage: storage),
      telemetry: hub,
    );
    storage.failWrite = true;
    final sub = trooper
        .watchKey('room', initialParameter: const ())
        .listen((_) {});
    await pumpEventQueue();

    source.add('frame');
    await pumpEventQueue();

    expect(
      events.map((e) => e.error),
      contains(isA<StateError>().having((e) => e.message, 'm', 'disk full')),
    );
    await sub.cancel();
    await trooper.dispose();
    await source.close();
  });
}
