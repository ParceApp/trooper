import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class _InFlightController extends TrooperController {
  late final itemQuery = query<String, ({int id})>(
    namespace: 'in_flight_items',
    cancellableFetch: (param, token) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.throwIfCancelled();
      return 'Item ${param.id}';
    },
  );
}

void main() {
  group('Edge Case: Controller Disposal During In-Flight Requests', () {
    test('disposing controller with 20 active queries causes no unhandled exceptions',
        () async {
      final controller = _InFlightController();

      // Launch 20 in-flight queries
      final futures = List.generate(
        20,
        (i) => controller.itemQuery.get((id: i)).then<Object?>(
              (val) => val,
              onError: (Object err) => err,
            ),
      );

      // Immediately dispose the controller while requests are in-flight
      await controller.dispose();
      expect(controller.isDisposed, isTrue);

      final results = await Future.wait(futures);
      expect(results.length, 20);

      // All callers should have completed safely without crashing
      for (final r in results) {
        expect(r, isNotNull);
      }
    });
  });
}
