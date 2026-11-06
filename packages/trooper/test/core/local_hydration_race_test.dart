import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_storage_backend.dart';

/// Holds every read open until [releaseReads], then returns what storage held
/// when the read started, as a slow real backend can.
class _GatedStorage extends MockStorageBackend {
  final List<Completer<void>> _gates = [];

  @override
  Future<String?> read(String key) async {
    readCount++;
    final snapshot = entries[key];
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    if (failOnRead) {
      throw const FileSystemException('Simulated disk read failure');
    }
    return snapshot;
  }

  Future<void> releaseReads() async {
    for (final gate in _gates) {
      gate.complete();
    }
    _gates.clear();
    await pumpEventQueue();
  }
}

/// A value with a field the codec leaves out on purpose, like a search query
/// that lives in the URL and not in storage.
typedef _Filter = ({String query, String sort});

const _Filter _initial = (query: '', sort: 'initial');
const _Filter _saved = (query: '', sort: 'saved');
const _Filter _next = (query: 'hue', sort: 'next');

final _codec = TrooperCodec.custom<_Filter>(
  to: (filter) => filter.sort,
  from: (sort) => (query: '', sort: sort),
);

/// Ways the running read can find storage unusable. Each one makes the read
/// delete the entry, which must not delete a value set in the meantime.
final Map<String, Future<void> Function(_GatedStorage, String)> _unusableReads =
    {
      'a malformed entry': (storage, key) =>
          storage.write(key, 'not an envelope'),
      'an expired entry': (storage, key) => storage.write(
        key,
        StorageEnvelope(
          payload: 'saved',
          createdAt: DateTime(2020),
          expiresAt: DateTime(2021),
        ).encode(),
      ),
      'a failing read': (storage, key) async => storage.failOnRead = true,
    };

String? _storedPayload(_GatedStorage storage, String key) {
  final raw = storage.entries[key];
  return raw == null ? null : StorageEnvelope.tryDecode(raw)?.payload;
}

void main() {
  late _GatedStorage storage;

  setUp(() {
    storage = _GatedStorage();
  });

  group('LocalTrooper hydration race', () {
    final storageKey = QueryKey('filter', const ()).storageKey;

    LocalTrooper<_Filter, ()> build({void Function(_Filter value)? onData}) {
      final trooper = LocalTrooper<_Filter, ()>(
        namespace: 'filter',
        initialValue: _initial,
        codec: _codec,
        config: TrooperConfig(storage: storage),
        sideEffects: onData == null
            ? null
            : TrooperSideEffects(onData: (value, _) => onData(value)),
      );
      addTearDown(trooper.dispose);
      return trooper;
    }

    Future<void> seedSaved() => storage.write(
      storageKey,
      StorageEnvelope(payload: 'saved', createdAt: DateTime.now()).encode(),
    );

    test('a read already running does not overwrite set()', () async {
      await seedSaved();
      final seen = <_Filter>[];
      final trooper = build(onData: seen.add);
      final emitted = <_Filter>[];
      final sub = trooper.stream.dataStream.listen(emitted.add);
      addTearDown(sub.cancel);

      final read = trooper.get(const ());
      trooper.set(_next, const ());
      await storage.releaseReads();

      expect(await read, _next);
      expect(trooper.currentData(), _next);
      expect(emitted, [_initial, _next]);
      expect(seen, [_next]);
    });

    test(
      'a read started after set() keeps the fields the codec drops',
      () async {
        final trooper = build();

        trooper.set(_next, const ());
        final read = trooper.get(const ());
        await storage.releaseReads();

        expect(await read, _next);
        expect(trooper.currentData(), _next);
      },
    );

    test('set() ends hydration, so an eager watch starts no read', () {
      final trooper = build();

      trooper.set(_next, const ());
      trooper.watch(initialParameter: const (), eager: true);

      expect(trooper.isHydrated, isTrue);
      expect(storage.readCount, 0);
    });

    test('reads running together apply the stored value once', () async {
      await seedSaved();
      final seen = <_Filter>[];
      final trooper = build(onData: seen.add);

      final first = trooper.get(const ());
      final second = trooper.get(const ());
      await storage.releaseReads();

      expect(await first, _saved);
      expect(await second, _saved);
      expect(seen, [_saved]);
      expect(trooper.isHydrated, isTrue);
    });

    for (final MapEntry(key: name, value: prepare) in _unusableReads.entries) {
      test('a running read that hits $name keeps the value of set()', () async {
        await seedSaved();
        await prepare(storage, storageKey);
        final trooper = build();

        final read = trooper.get(const ());
        trooper.set(_next, const ());
        await storage.releaseReads();

        expect(await read, _next);
        expect(_storedPayload(storage, storageKey), 'next');
      });
    }

    test('a read already running does not undo reset()', () async {
      await seedSaved();
      final trooper = build();

      final read = trooper.get(const ());
      trooper.reset(const ());
      await storage.releaseReads();

      expect(await read, _initial);
      expect(trooper.currentData(), _initial);
      expect(storage.entries, isEmpty);
    });

    test('a read already running does not undo invalidate()', () async {
      await seedSaved();
      final seen = <_Filter>[];
      final trooper = build(onData: seen.add);

      final read = trooper.get(const ());
      trooper.invalidate();
      await storage.releaseReads();

      expect(await read, _initial);
      expect(trooper.current(), isA<DataInitial<_Filter>>());
      expect(trooper.isHydrated, isFalse);
      expect(seen, isEmpty);
    });

    test(
      'a failing read does not mark hydration done after invalidate()',
      () async {
        storage.failOnRead = true;
        final trooper = build();

        final read = trooper.get(const ());
        trooper.invalidate();
        await storage.releaseReads();

        expect(await read, _initial);
        expect(trooper.isHydrated, isFalse);
      },
    );
  });

  group('KeyedLocalTrooper hydration race', () {
    final storageKey = QueryKey.keyed(
      'filters',
      key: 'a',
      parameter: const (),
    ).storageKey;

    KeyedLocalTrooper<String, _Filter, ()> build({
      void Function(String key, _Filter value)? onData,
    }) {
      final trooper = KeyedLocalTrooper<String, _Filter, ()>(
        namespace: 'filters',
        initialValue: _initial,
        codec: _codec,
        config: TrooperConfig(storage: storage),
        sideEffects: onData == null
            ? null
            : KeyedTrooperSideEffects(
                onData: (key, value, _) => onData(key, value),
              ),
      );
      addTearDown(trooper.dispose);
      return trooper;
    }

    Future<void> seedSaved() => storage.write(
      storageKey,
      StorageEnvelope(payload: 'saved', createdAt: DateTime.now()).encode(),
    );

    test('a read already running does not overwrite setKey()', () async {
      await seedSaved();
      final seen = <_Filter>[];
      final trooper = build(onData: (_, value) => seen.add(value));

      final read = trooper.getKey('a', const ());
      trooper.setKey('a', _next, const ());
      await storage.releaseReads();

      expect(await read, _next);
      expect(trooper.currentKeyData('a'), _next);
      expect(seen, [_next]);
    });

    test(
      'a read started after setKey() keeps the fields the codec drops',
      () async {
        final trooper = build();

        trooper.setKey('a', _next, const ());
        // A fresh L1 entry would answer getKey, so force it down to hydration.
        final read = trooper.refreshKey('a', const ());
        await storage.releaseReads();

        expect(await read, _next);
        expect(trooper.currentKeyData('a'), _next);
      },
    );

    test('setKey() ends hydration for its own key only', () async {
      await seedSaved();
      final trooper = build();

      final read = trooper.getKey('a', const ());
      trooper.setKey('b', _next, const ());
      await storage.releaseReads();

      expect(await read, _saved);
      expect(trooper.currentKeyData('a'), _saved);
      expect(trooper.currentKeyData('b'), _next);
      expect(trooper.isHydratedKey('a'), isTrue);
      expect(trooper.isHydratedKey('b'), isTrue);
    });

    test('reads running together apply the stored value once', () async {
      await seedSaved();
      final seen = <_Filter>[];
      final trooper = build(onData: (_, value) => seen.add(value));

      final first = trooper.refreshKey('a', const ());
      final second = trooper.refreshKey('a', const ());
      await storage.releaseReads();

      expect(await first, _saved);
      expect(await second, _saved);
      expect(seen, [_saved]);
    });

    for (final MapEntry(key: name, value: prepare) in _unusableReads.entries) {
      test(
        'a running read that hits $name keeps the value of setKey()',
        () async {
          await seedSaved();
          await prepare(storage, storageKey);
          final trooper = build();

          final read = trooper.getKey('a', const ());
          trooper.setKey('a', _next, const ());
          await storage.releaseReads();

          expect(await read, _next);
          expect(_storedPayload(storage, storageKey), 'next');
        },
      );
    }
  });
}
