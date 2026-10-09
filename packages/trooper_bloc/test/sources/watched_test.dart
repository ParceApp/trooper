import 'package:flutter_test/flutter_test.dart';
import 'package:trooper/trooper.dart';
import 'package:trooper_bloc/src/sources/watched.dart';
import 'package:trooper_bloc/testing.dart';

void main() {
  group('WatchedHandle', () {
    test('initializes state synchronously from accessor.current()', () {
      final fake = FakeAccessor<String, ()>(initialData: 'hello');
      final handle = WatchedHandle<String, ()>(
        accessor: fake,
        parameter: const (),
        onUpdate: (_) {},
      );

      expect(handle.state, isA<DataLoaded<String>>());
      expect(handle.hasData, isTrue);
      expect(handle.dataOrNull, 'hello');
      expect(handle.isLoading, isFalse);
      expect(handle.isError, isFalse);
    });

    test('updates state and invokes onUpdate callback when stream emits', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'v1');
      var updateCalls = 0;
      final handle = WatchedHandle<String, ()>(
        accessor: fake,
        parameter: const (),
        onUpdate: (_) => updateCalls++,
      );
      handle.attach();

      expect(updateCalls, 0);

      fake.emitData('v2');
      await pumpEventQueue();

      expect(handle.dataOrNull, 'v2');
      expect(updateCalls, 1);
    });

    test('snapshot locking freezes state while liveState continues to update', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'initial');
      final handle = WatchedHandle<String, ()>(
        accessor: fake,
        parameter: const (),
        onUpdate: (_) {},
      );
      handle.attach();

      expect(handle.state.dataOrNull, 'initial');
      expect(handle.liveState.dataOrNull, 'initial');

      // Lock snapshot
      handle.lockSnapshot();

      // Emit new background data to fake accessor
      fake.emitData('background_update');
      await pumpEventQueue();

      // handle.state remains locked to 'initial'
      expect(handle.state.dataOrNull, 'initial');
      // liveState reflects background emission
      expect(handle.liveState.dataOrNull, 'background_update');

      // Unlock snapshot
      handle.unlockSnapshot();
      expect(handle.state.dataOrNull, 'background_update');
    });

    test('supports dynamic parameter switching', () async {
      final fake = FakeAccessor<String, ({int id})>();
      var updateCalls = 0;
      final handle = WatchedHandle<String, ({int id})>(
        accessor: fake,
        parameter: (id: 1),
        onUpdate: (_) => updateCalls++,
      );
      handle.attach();

      expect(handle.parameter, (id: 1));

      handle.parameter = (id: 2);
      expect(handle.parameter, (id: 2));
      expect(updateCalls, 1);

      fake.emitData('item-2');
      await pumpEventQueue();
      expect(handle.dataOrNull, 'item-2');
    });

    test('supports dynamic source switching', () async {
      final fake1 = FakeAccessor<String, ()>(initialData: 'source-1');
      final fake2 = FakeAccessor<String, ()>(initialData: 'source-2');
      var updateCalls = 0;
      final handle = WatchedHandle<String, ()>(
        accessor: fake1,
        parameter: const (),
        onUpdate: (_) => updateCalls++,
      );
      handle.attach();

      expect(handle.dataOrNull, 'source-1');

      handle.source = fake2;
      expect(handle.dataOrNull, 'source-2');
      expect(updateCalls, 1);
    });

    test('pause and resume lifecycle buffers stream events', () async {
      final fake = FakeAccessor<int, ()>(initialData: 10);
      var updateCalls = 0;
      final handle = WatchedHandle<int, ()>(
        accessor: fake,
        parameter: const (),
        onUpdate: (_) => updateCalls++,
      );
      handle.attach();

      handle.pause();
      fake.emitData(20);
      await pumpEventQueue();
      // Should not have triggered while paused
      expect(updateCalls, 0);

      handle.resume();
      await pumpEventQueue();
      // Resume delivers pending transition
      expect(handle.dataOrNull, 20);
      expect(updateCalls, 1);
    });

    test('disposal cancels subscription and ignores further updates', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'init');
      var updateCalls = 0;
      final handle = WatchedHandle<String, ()>(
        accessor: fake,
        parameter: const (),
        onUpdate: (_) => updateCalls++,
      );
      handle.attach();

      await handle.dispose();
      fake.emitData('after-dispose');
      await pumpEventQueue();

      expect(updateCalls, 0);

      // Refresh on disposed handle throws StateError
      expect(handle.refresh, throwsStateError);

      // Assigning parameter or source when disposed is a no-op
      handle.parameter = const ();
      handle.source = fake;
    });

    test('exposes backing accessor and handles stream errors', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'initial');
      var updateCalls = 0;
      final handle = WatchedHandle<String, ()>(
        accessor: fake,
        parameter: const (),
        onUpdate: (_) => updateCalls++,
      );
      handle.attach();

      expect(identical(handle.accessor, fake), isTrue);

      // Setting identical parameter or source is a no-op
      handle.parameter = const ();
      handle.source = fake;
      expect(updateCalls, 0);

      fake.emitError('network-failure');
      await pumpEventQueue();

      expect(handle.isError, isTrue);
      expect(handle.state, isA<DataError<String>>());
      expect(updateCalls, 1);

      fake.emitStreamError('raw-stream-error');
      await pumpEventQueue();

      expect(handle.isError, isTrue);
      expect((handle.state as DataError<String>).error, 'raw-stream-error');
      expect(updateCalls, 2);

      await handle.dispose();
    });
  });
}
