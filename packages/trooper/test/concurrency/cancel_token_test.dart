import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperCancelToken', () {
    test('initial state is uncancelled with null reason', () {
      final token = TrooperCancelToken();
      expect(token.isCancelled, isFalse);
      expect(token.reason, isNull);
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('cancel sets isCancelled and triggers registered listeners', () {
      final token = TrooperCancelToken();
      var called = false;

      token.onCancel(() {
        called = true;
      });

      token.cancel(reason: 'User navigated away');

      expect(token.isCancelled, isTrue);
      expect(token.reason, 'User navigated away');
      expect(called, isTrue);
      expect(
        () => token.throwIfCancelled(),
        throwsA(
          isA<TrooperCancelledException>().having(
            (e) => e.message,
            'message',
            'User navigated away',
          ),
        ),
      );
    });

    test('cancel is idempotent and only invokes listeners once', () {
      final token = TrooperCancelToken();
      var count = 0;

      token.onCancel(() {
        count++;
      });

      token.cancel(reason: 'First cancellation');
      token.cancel(reason: 'Second cancellation');

      expect(count, 1);
      expect(token.reason, 'First cancellation');
    });

    test(
      'registering listener on already cancelled token executes immediately',
      () {
        final token = TrooperCancelToken();
        token.cancel(reason: 'Already dead');

        var invoked = false;
        token.onCancel(() {
          invoked = true;
        });

        expect(invoked, isTrue);
      },
    );

    test('removeListener prevents callback execution on subsequent cancel', () {
      final token = TrooperCancelToken();
      var invoked = false;

      final unsubscribe = token.onCancel(() {
        invoked = true;
      });

      unsubscribe();
      token.cancel(reason: 'Cancelled');

      expect(invoked, isFalse);
    });
  });
}
