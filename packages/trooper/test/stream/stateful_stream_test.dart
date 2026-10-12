import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('StatefulStream', () {
    test('synchronous inspection getters reflect current state correctly', () {
      final controller = StatefulStreamController<String>();
      final stream = controller.stream;

      expect(stream.isInitial, isTrue);
      expect(stream.isLoaded, isFalse);
      expect(stream.isLoading, isFalse);
      expect(stream.isError, isFalse);
      expect(stream.isRefreshing, isFalse);
      expect(stream.currentData, isNull);

      controller.emitLoading(progress: 0.2);
      expect(stream.isLoading, isTrue);
      expect(stream.isInitial, isFalse);

      controller.emitData('active_data');
      expect(stream.isLoaded, isTrue);
      expect(stream.currentData, 'active_data');
      expect(stream.isLoading, isFalse);

      controller.emitRefreshing('active_data');
      expect(stream.isRefreshing, isTrue);
      expect(stream.isLoaded, isTrue);
      expect(stream.isLoading, isTrue);
      expect(stream.currentData, 'active_data');

      controller.emitError('failed');
      expect(stream.isError, isTrue);
      expect(stream.isLoaded, isFalse);
      expect(stream.isLoading, isFalse);

      controller.dispose();
    });

    test(
      'dataStream filters out non-data states and delivers payloads',
      () async {
        final controller = StatefulStreamController<int>();
        final stream = controller.stream;

        final dataEvents = <int>[];
        final sub = stream.dataStream.listen(dataEvents.add);

        controller.emitLoading();
        controller.emitData(10);
        controller.emitRefreshing(10);
        controller.emitError('oops');
        controller.emitData(20);

        await Future<void>.delayed(Duration.zero);

        expect(dataEvents, [10, 10, 20]);

        await sub.cancel();
        await controller.dispose();
      },
    );

    test(
      'errorStream delivers only error objects from DataError states',
      () async {
        final controller = StatefulStreamController<String>();
        final stream = controller.stream;

        final errors = <Object>[];
        final sub = stream.errorStream.listen(errors.add);

        controller.emitData('ok');
        controller.emitError(FormatException('bad json'));
        controller.emitLoading();
        controller.emitError(StateError('not ready'));

        await Future<void>.delayed(Duration.zero);

        expect(errors.length, 2);
        expect(errors.first, isA<FormatException>());
        expect(errors.last, isA<StateError>());

        await sub.cancel();
        await controller.dispose();
      },
    );

    test('loadingStream deduplicates loading transitions', () async {
      final controller = StatefulStreamController<String>();
      final stream = controller.stream;

      final loadingStates = <bool>[];
      final sub = stream.loadingStream.listen(loadingStates.add);

      // Initial state isInitial -> isLoading = false
      await Future<void>.delayed(Duration.zero);

      controller.emitLoading(); // true
      controller.emitLoading(
        progress: 0.5,
      ); // still true -> should be deduplicated
      controller.emitData('ready'); // false
      controller.emitRefreshing('ready'); // true
      controller.emitData('updated'); // false

      await Future<void>.delayed(Duration.zero);

      expect(loadingStates, [false, true, false, true, false]);

      await sub.cancel();
      await controller.dispose();
    });

    test('mapData transforms data payloads across states', () async {
      final controller = StatefulStreamController<int>();
      final mappedStream = controller.stream.mapData((n) => 'Number $n');

      final emitted = <StatefulData<String>>[];
      final sub = mappedStream.listen(emitted.add);

      controller.emitInitial();
      controller.emitLoading(progress: 0.1);
      controller.emitData(42);
      controller.emitRefreshing(42, progress: 0.8);
      controller.emitError('network', staleData: 42);

      await Future<void>.delayed(Duration.zero);

      expect(
        emitted.length,
        6,
      ); // Includes initial replayed state + 5 emissions
      expect(emitted[1], isA<DataInitial<String>>());
      expect(emitted[2], isA<DataLoading<String>>());
      expect(emitted[3].dataOrNull, 'Number 42');
      expect(emitted[4], isA<DataRefreshing<String>>());
      expect(emitted[4].dataOrNull, 'Number 42');
      expect((emitted[5] as DataError<String>).staleData, 'Number 42');

      await sub.cancel();
      await controller.dispose();
    });

    test(
      'skipCurrent skips replaying current state to new listeners',
      () async {
        final controller = StatefulStreamController<String>();
        controller.emitData('initial_data');

        final skippingStream = controller.stream.skipCurrent();
        expect(skippingStream.skipInitialState, isTrue);
        expect(skippingStream.currentData, 'initial_data');

        // Calling skipCurrent on already skipping stream returns itself
        expect(skippingStream.skipCurrent(), same(skippingStream));

        final events = <String>[];
        final sub = skippingStream.dataStream.listen(events.add);

        await Future<void>.delayed(Duration.zero);
        // Initial data should not have been emitted to subscriber
        expect(events, isEmpty);

        controller.emitData('new_data');
        await Future<void>.delayed(Duration.zero);
        expect(events, ['new_data']);

        await sub.cancel();
        await controller.dispose();
      },
    );
  });
}
