import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_api_client.dart';
import '../fixtures/mock_storage_backend.dart';

void main() {
  group('QueryTrooper', () {
    late MockApiClient<({int id}), String> api;
    late MockStorageBackend storage;

    setUp(() {
      api = MockApiClient<({int id}), String>();
      storage = MockStorageBackend();
    });

    test(
      'fresh cache hit returns immediately without second network call',
      () async {
        api.defaultResponse = 'User Alice';
        final query = QueryTrooper<String, ({int id})>(
          namespace: 'users',
          fetch: api.fetch,
          config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
        );

        final first = await query.get((id: 1));
        expect(first, 'User Alice');
        expect(api.callCount, 1);
        expect(query.current().isLoaded, isTrue);

        final second = await query.get((id: 1));
        expect(second, 'User Alice');
        expect(api.callCount, 1); // Hit L1 cache, no second call
      },
    );

    test(
      'deduplicates concurrent requests into a single network call',
      () async {
        final completer = Completer<String>();
        api.deferredCompleter = completer;

        final query = QueryTrooper<String, ({int id})>(
          namespace: 'users',
          fetch: api.fetch,
          config: const TrooperConfig(deduplicate: true),
        );

        // Launch 50 concurrent get requests for the same parameter
        final futures = List.generate(50, (_) => query.get((id: 42)));

        expect(api.callCount, 1); // Exactly one network request sent

        completer.complete('Concurrent Result');
        final results = await Future.wait(futures);

        for (final r in results) {
          expect(r, 'Concurrent Result');
        }
        expect(api.callCount, 1);
      },
    );

    test(
      'SWR background revalidation emits DataRefreshing and preserves data',
      () async {
        var call = 0;
        final query = QueryTrooper<String, ()>(
          namespace: 'clock',
          fetch: (_) async {
            call++;
            return 'Version $call';
          },
          config: const TrooperConfig(
            timeToLive: Duration(milliseconds: 20),
            stalePolicy: StalePolicy.keepStaleWhileRevalidate,
          ),
        );

        final states = <StatefulData<String>>[];
        final sub = query.stream.listen(states.add);

        // Initial fetch
        final v1 = await query.get(const ());
        expect(v1, 'Version 1');
        expect(query.currentData(), 'Version 1');
        expect(query.current(), isA<DataLoaded<String>>());

        // Wait past TTL
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Next get should return stale data immediately and trigger SWR
        final vStale = await query.get(const ());
        expect(vStale, 'Version 1');

        // Wait for background revalidation to complete
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.any((s) => s is DataRefreshing<String>), isTrue);
        final refreshingState =
            states.firstWhere((s) => s is DataRefreshing<String>)
                as DataRefreshing<String>;
        expect(refreshingState.data, 'Version 1');

        expect(query.currentData(), 'Version 2');
        expect(call, 2);

        await sub.cancel();
      },
    );

    test(
      'conflict policy cancel aborts prior request with exception',
      () async {
        final completer1 = Completer<String>();
        final completer2 = Completer<String>();

        var callNum = 0;
        final query = QueryTrooper<String, ({String query})>.cancellable(
          namespace: 'search',
          fetch: (param, token) {
            callNum++;
            if (callNum == 1) {
              token.onCancel(() {
                if (!completer1.isCompleted) {
                  completer1.completeError(
                    const TrooperCancelledException(message: 'Cancelled'),
                  );
                }
              });
              return completer1.future;
            } else {
              return completer2.future;
            }
          },
          config: const TrooperConfig(
            conflictPolicy: QueryConflictPolicy.cancel,
            deduplicate: false,
          ),
        );

        final req1 = query.get((query: 'flutter'));
        final req2 = query.get((query: 'flutter dart'));

        completer2.complete('Result 2');

        expect(req1, throwsA(isA<TrooperCancelledException>()));
        expect(await req2, 'Result 2');
      },
    );

    test(
      'conflict policy forward forwards prior caller to new request',
      () async {
        final completer1 = Completer<String>();
        final completer2 = Completer<String>();

        var callNum = 0;
        final query = QueryTrooper<String, ({String filter})>.cancellable(
          namespace: 'items',
          fetch: (param, token) {
            callNum++;
            return callNum == 1 ? completer1.future : completer2.future;
          },
          config: const TrooperConfig(
            conflictPolicy: QueryConflictPolicy.forward,
            deduplicate: false,
          ),
        );

        final req1 = query.get((filter: 'active'));
        final req2 = query.get((filter: 'archived'));

        completer2.complete('Archived Items');

        // Both callers should resolve with the newest result
        final res1 = await req1;
        final res2 = await req2;
        expect(res1, 'Archived Items');
        expect(res2, 'Archived Items');
      },
    );

    test(
      'persists to L2 with StorageEnvelope and hydratizes correctly',
      () async {
        api.defaultResponse = 'Saved Payload';
        final query = QueryTrooper<String, ({int id})>(
          namespace: 'persisted_user',
          fetch: api.fetch,
          codec: TrooperCodec.string,
          config: TrooperConfig(
            storage: storage,
            timeToLive: const Duration(hours: 1),
          ),
        );

        await query.get((id: 10));

        expect(storage.writeCount, 1);
        final rawEnvelope = storage.entries.values.first;
        final envelope = StorageEnvelope.tryDecode(rawEnvelope);
        expect(envelope, isNotNull);
        expect(envelope!.payload, 'Saved Payload');
        expect(envelope.isExpired, isFalse);

        // Simulate app restart with a fresh query instance sharing the same storage
        final restoredQuery = QueryTrooper<String, ({int id})>(
          namespace: 'persisted_user',
          fetch: (_) async => throw StateError('Should not hit API'),
          codec: TrooperCodec.string,
          config: TrooperConfig(
            storage: storage,
            timeToLive: const Duration(hours: 1),
          ),
        );

        final restored = await restoredQuery.get((id: 10));
        expect(restored, 'Saved Payload');
        expect(restoredQuery.current(), isA<DataLoaded<String>>());
      },
    );

    test(
      'expired L2 data with keepStaleWhileRevalidate triggers SWR on startup',
      () async {
        final now = DateTime.now();
        final expiredEnvelope = StorageEnvelope(
          payload: 'Stale Disk Data',
          createdAt: now.subtract(const Duration(days: 3)),
          expiresAt: now.subtract(const Duration(days: 1)),
          timeToLiveMillis: const Duration(hours: 1).inMilliseconds,
        );

        final key = const QueryKey('swr_user', ());
        await storage.write(key.storageKey, expiredEnvelope.encode());

        var refreshed = false;
        final query = QueryTrooper<String, ()>(
          namespace: 'swr_user',
          fetch: (_) async {
            refreshed = true;
            return 'Fresh Network Data';
          },
          codec: TrooperCodec.string,
          config: TrooperConfig(
            storage: storage,
            timeToLive: const Duration(hours: 1),
            stalePolicy: StalePolicy.keepStaleWhileRevalidate,
          ),
        );

        // get() should immediately return stale data while background revalidating
        final immediateData = await query.get(const ());
        expect(immediateData, 'Stale Disk Data');

        // Allow background revalidation to complete
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(refreshed, isTrue);
        expect(query.currentData(), 'Fresh Network Data');
      },
    );

    test(
      'expired L2 data with discardStaleOnRefresh deletes from storage',
      () async {
        final now = DateTime.now();
        final expiredEnvelope = StorageEnvelope(
          payload: 'Discarded Disk Data',
          createdAt: now.subtract(const Duration(days: 3)),
          expiresAt: now.subtract(const Duration(days: 1)),
          timeToLiveMillis: const Duration(hours: 1).inMilliseconds,
        );

        final key = const QueryKey('discard_user', ());
        await storage.write(key.storageKey, expiredEnvelope.encode());

        final query = QueryTrooper<String, ()>(
          namespace: 'discard_user',
          fetch: (_) async => 'Fresh Network Data',
          codec: TrooperCodec.string,
          config: TrooperConfig(
            storage: storage,
            timeToLive: const Duration(hours: 1),
            stalePolicy: StalePolicy.discardStaleOnRefresh,
          ),
        );

        final data = await query.get(const ());
        expect(data, 'Fresh Network Data');
        expect(storage.deleteCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'emits DataError on failure and retains staleData when available',
      () async {
        var shouldFail = false;
        final query = QueryTrooper<String, ()>(
          namespace: 'error_user',
          fetch: (_) async {
            if (shouldFail) throw Exception('API Outage');
            return 'Valid Data';
          },
          config: const TrooperConfig(timeToLive: Duration(milliseconds: 10)),
        );

        await query.get(const ());
        expect(query.currentData(), 'Valid Data');

        // Force failure
        shouldFail = true;
        try {
          await query.refresh(const ());
          fail('Should have thrown');
        } catch (e) {
          expect(e.toString(), contains('API Outage'));
        }

        final errState = query.current();
        expect(errState, isA<DataError<String>>());
        expect((errState as DataError<String>).staleData, 'Valid Data');

        // Test recover
        shouldFail = false;
        query.recover();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(query.currentData(), 'Valid Data');

        query.dispose();
      },
    );

    test('trigger background fetch and lifecycle hooks', () async {
      var fetchCount = 0;
      final query = QueryTrooper<String, ()>(
        namespace: 'trigger_ns',
        fetch: (_) async {
          fetchCount++;
          return 'Result $fetchCount';
        },
      );

      query.trigger(const ());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fetchCount, 1);
      expect(query.currentData(), 'Result 1');

      query.pause();
      query.resume();
      query.didChangeDependencies();

      query.dispose();
    });

    test('sideEffects callbacks execute during query lifecycle', () async {
      var started = false;
      var transformed = false;
      var dataCallback = false;

      final query = QueryTrooper<String, ()>(
        namespace: 'callbacks_ns',
        fetch: (_) async => 'Callback Payload',
        sideEffects: TrooperSideEffects(
          onRequestStarted: (_) => started = true,
          transformRequestResult: (data, _) {
            transformed = true;
            return '$data (transformed)';
          },
          onData: (_, _) => dataCallback = true,
        ),
      );

      final result = await query.get(const ());
      expect(result, 'Callback Payload (transformed)');
      expect(query.currentData(), 'Callback Payload (transformed)');
      expect(started, isTrue);
      expect(transformed, isTrue);
      expect(dataCallback, isTrue);

      query.dispose();
    });

    test('conflict policy parallel allows simultaneous execution', () async {
      final query = QueryTrooper<String, ({int delay})>(
        namespace: 'parallel_ns',
        fetch: (p) async {
          await Future<void>.delayed(Duration(milliseconds: p.delay));
          return 'Done ${p.delay}';
        },
        config: const TrooperConfig(
          conflictPolicy: QueryConflictPolicy.parallel,
          deduplicate: false,
        ),
      );

      final f1 = query.get((delay: 20));
      final f2 = query.get((delay: 5));

      final results = await Future.wait([f1, f2]);
      expect(results, ['Done 20', 'Done 5']);

      query.dispose();
    });

    test('QueryTrooper.set persists to L2 storage', () async {
      final storage = InMemoryStorageBackend();
      final codec = TrooperCodec.string;

      final query = QueryTrooper<String, ()>(
        namespace: 'set_storage_ns',
        fetch: (_) async => 'Network',
        codec: codec,
        config: TrooperConfig(storage: storage),
      );

      final returned = query.set('Manual Value', const ());
      expect(returned, 'Manual Value');
      expect(query.currentData(), 'Manual Value');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      const key = QueryKey('set_storage_ns', ());
      final raw = await storage.read(key.storageKey);
      expect(raw, isNotNull);

      query.dispose();
    });
  });

  group('QueryConflictPolicy.parallel', () {
    test('late error of an older request keeps the newer data', () async {
      final calls = <Completer<String>>[];
      final query = QueryTrooper<String, ()>(
        namespace: 'parallel_error',
        fetch: (_) => (calls..add(Completer<String>())).last.future,
        config: TrooperConfig(
          deduplicate: false,
          conflictPolicy: QueryConflictPolicy.parallel,
        ),
      );
      final older = query.get((), forceRefresh: true);
      final newer = query.get((), forceRefresh: true);
      await Future<void>.value();
      calls[1].complete('new');
      expect(await newer, 'new');
      calls[0].completeError(StateError('late failure'));
      await expectLater(older, throwsStateError);
      expect(query.current(), isA<DataLoaded<String>>());
      expect(query.currentData(), 'new');
      await query.dispose();
    });
  });
}
