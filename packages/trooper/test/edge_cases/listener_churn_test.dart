import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

import '../fixtures/mock_stream_source.dart';

void main() {
  group('Edge Case: Listener Churn and Stream Subscription Safety', () {
    test('1000 rapid listen and cancel cycles on QueryTrooper leave stream controller healthy',
        () async {
      final query = QueryTrooper<int, ()>(
        namespace: 'churn_counter',
        fetch: (_) async => 42,
        config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
      );

      final stream = query.watch();

      for (var i = 0; i < 1000; i++) {
        final sub = stream.listen((_) {});
        await sub.cancel();
      }

      // Stream should still work normally after 1000 cancels
      final stateCompleter = Completer<StatefulData<int>>();
      final finalSub = stream.listen((state) {
        if (!stateCompleter.isCompleted && state.isLoaded) {
          stateCompleter.complete(state);
        }
      });

      await query.get(const ());
      final loadedState = await stateCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      expect(loadedState, isA<DataLoaded<int>>());
      expect((loadedState as DataLoaded<int>).data, 42);

      await finalSub.cancel();
      query.dispose();
    });

    test('rapid listen and cancel cycles on StreamTrooper with keepAlive false handle connect/disconnect cleanly',
        () async {
      final source = MockStreamSource<String>();
      var connects = 0;
      var disconnects = 0;

      final streamTrooper = StreamTrooper<String, ()>(
        namespace: 'churn_stream',
        streamFactory: (_, _) => source.stream,
        onConnect: (_, _) => connects++,
        onDisconnect: () => disconnects++,
        keepAlive: false,
      );

      final watcher = streamTrooper.watch(initialParameter: const ());

      for (var i = 0; i < 50; i++) {
        final sub = watcher.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await Future<void>.delayed(Duration.zero);
      }

      // After all cancels, it should be disconnected
      expect(streamTrooper.isConnected, isFalse);
      expect(connects, greaterThanOrEqualTo(1));
      expect(disconnects, greaterThanOrEqualTo(1));

      // Final subscription connects and receives events
      final eventCompleter = Completer<String>();
      final finalSub = watcher.dataStream.listen(eventCompleter.complete);

      await Future<void>.delayed(Duration.zero);
      expect(streamTrooper.isConnected, isTrue);

      source.emit('Event after churn');
      final received = await eventCompleter.future.timeout(
        const Duration(seconds: 1),
      );
      expect(received, 'Event after churn');

      await finalSub.cancel();
      await streamTrooper.dispose();
      await source.close();
    });
  });
}
