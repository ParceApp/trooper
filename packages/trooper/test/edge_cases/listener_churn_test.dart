import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('Edge Case: Listener Churn and Stream Subscription Safety', () {
    test('1000 rapid listen and cancel cycles leave stream controller healthy',
        () async {
      final query = TrooperQuery<int, ()>(
        namespace: 'churn_counter',
        fetch: (_) async => 42,
        config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
      );

      final stream = query.watch(const ());

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
  });
}
