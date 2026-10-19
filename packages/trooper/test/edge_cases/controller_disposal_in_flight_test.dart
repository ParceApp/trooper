import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _InFlightController extends TrooperController {
  late final itemQuery = cancellableQuery<String, ({int id})>(
    namespace: 'in_flight_items',
    fetch: (param, token) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.throwIfCancelled();
      return 'Item ${param.id}';
    },
  );

  late final keyedItemQuery = keyedQuery<int, String, ()>(
    namespace: 'in_flight_keyed',
    fetch: (id, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return 'KeyedItem $id';
    },
  );

  late final localCounter = local<int, ()>(
    namespace: 'in_flight_local',
    initialValue: 0,
  );
}

void main() {
  group('Edge Case: Controller Disposal During In-Flight Requests', () {
    test(
      'disposing controller cancels all in-flight queries with TrooperCancelledException and shuts down children',
      () async {
        final controller = _InFlightController();
        // Ensure localCounter is instantiated and managed
        controller.localCounter;

        // Launch 20 in-flight queries
        final futures = List.generate(
          20,
          (i) => controller.itemQuery
              .get((id: i))
              .then<Object?>((val) => val, onError: (Object err) => err),
        );

        // Launch in-flight keyed query
        final keyedFuture = controller.keyedItemQuery
            .getKey(99, const ())
            .then<Object?>((val) => val, onError: (Object err) => err);

        // Immediately dispose the controller while requests are in-flight
        await controller.dispose();
        expect(controller.isDisposed, isTrue);

        final results = await Future.wait(futures);
        expect(results.length, 20);

        // Every single in-flight query was cancelled cleanly
        for (final r in results) {
          expect(r, isA<TrooperCancelledException>());
        }

        final keyedResult = await keyedFuture;
        expect(keyedResult, isA<TrooperCancelledException>());

        // Verify complete teardown of all child components and streams
        expect(controller.itemQuery.isDisposed, isTrue);
        expect(controller.itemQuery.streamController.isClosed, isTrue);

        expect(controller.keyedItemQuery.isDisposed, isTrue);
        expect(controller.keyedItemQuery.stream.isClosed, isTrue);

        expect(controller.localCounter.isDisposed, isTrue);
        expect(controller.localCounter.streamController.isClosed, isTrue);
      },
    );
  });
}
