import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('RetryPolicy Unit Tests', () {
    test('RetryPolicy.none() does not retry and has zero delay', () {
      final policy = RetryPolicy.none();
      expect(policy.maxRetries, 0);
      expect(policy.shouldRetry(Exception('boom'), 1), isFalse);
      expect(policy.delayForAttempt(1), Duration.zero);
    });

    test(
      'RetryPolicy.immediate() retries up to maxRetries with zero delay',
      () {
        final policy = const RetryPolicy.immediate(maxRetries: 3);
        expect(policy.maxRetries, 3);
        expect(policy.shouldRetry(Exception(), 1), isTrue);
        expect(policy.shouldRetry(Exception(), 2), isTrue);
        expect(policy.shouldRetry(Exception(), 3), isTrue);
        expect(policy.shouldRetry(Exception(), 4), isFalse);
        expect(policy.delayForAttempt(1), Duration.zero);
        expect(policy.delayForAttempt(3), Duration.zero);
      },
    );

    test(
      'RetryPolicy.linear() increments delay linearly and clamps to maxDelay',
      () {
        const policy = RetryPolicy.linear(
          maxRetries: 5,
          delay: Duration(milliseconds: 100),
          maxDelay: Duration(milliseconds: 220),
        );

        expect(policy.delayForAttempt(1), const Duration(milliseconds: 100));
        expect(policy.delayForAttempt(2), const Duration(milliseconds: 100));
        expect(policy.delayForAttempt(3), const Duration(milliseconds: 100));
      },
    );

    test(
      'RetryPolicy.exponential() multiplies delay and clamps to maxDelay',
      () {
        const policy = RetryPolicy.exponential(
          maxRetries: 5,
          initialDelay: Duration(milliseconds: 100),
          backoffMultiplier: 2,
          maxDelay: Duration(milliseconds: 350),
        );

        expect(policy.delayForAttempt(1), const Duration(milliseconds: 100));
        expect(policy.delayForAttempt(2), const Duration(milliseconds: 200));
        expect(
          policy.delayForAttempt(3),
          const Duration(milliseconds: 350),
        ); // Clamped
        expect(
          policy.delayForAttempt(4),
          const Duration(milliseconds: 350),
        ); // Clamped
      },
    );

    test('retryWhen filters errors conditionally', () {
      final policy = RetryPolicy.immediate(
        maxRetries: 2,
        retryWhen: (e) => e is FormatException,
      );

      expect(
        policy.shouldRetry(const FormatException('bad format'), 1),
        isTrue,
      );
      expect(policy.shouldRetry(ArgumentError('invalid arg'), 1), isFalse);
    });
  });

  group('RetryPolicy Integration with TrooperQueryQueue', () {
    late TrooperQueryQueue queue;
    final testKey = QueryKey('test_queue', const ());

    setUp(() {
      queue = TrooperQueryQueue();
    });

    tearDown(() async {
      await queue.dispose();
    });

    test(
      'retries failed query and returns value when retry succeeds',
      () async {
        var attempts = 0;
        final result = await queue.execute<String>(
          key: testKey,
          action: (token) async {
            attempts++;
            if (attempts < 3) {
              throw StateError('Temporary failure $attempts');
            }
            return 'success';
          },
          retryPolicy: const RetryPolicy.immediate(maxRetries: 3),
        );

        expect(result, 'success');
        expect(attempts, 3);
      },
    );

    test('exhausts retries and rethrows original exception', () async {
      var attempts = 0;
      await expectLater(
        () => queue.execute<String>(
          key: testKey,
          action: (token) async {
            attempts++;
            throw StateError('Permanent failure');
          },
          retryPolicy: const RetryPolicy.immediate(maxRetries: 2),
        ),
        throwsA(isA<StateError>()),
      );

      // Initial run (1) + 2 retries = 3 total attempts
      expect(attempts, 3);
    });

    test('cancelling token during retry stops further attempts', () async {
      var attempts = 0;
      final token = TrooperCancelToken();

      final future = queue.execute<String>(
        key: testKey,
        action: (t) async {
          attempts++;
          throw StateError('Failure $attempts');
        },
        retryPolicy: const RetryPolicy.linear(
          maxRetries: 5,
          delay: Duration(milliseconds: 80),
        ),
      );

      // Let first attempt fail and enter delay
      await Future<void>.delayed(const Duration(milliseconds: 20));
      queue.cancel(testKey);

      await expectLater(future, throwsA(isA<TrooperCancelledException>()));
      final finalAttempts = attempts;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(attempts, finalAttempts);
      token.cancel();
    });
  });

  group('RetryPolicy Integration with QueryTrooper', () {
    test(
      'QueryTrooper retries automatically according to config.retryPolicy',
      () async {
        var fetchCount = 0;
        final query = QueryTrooper<String, ()>(
          namespace: 'retry_query',
          config: const TrooperConfig(
            timeToLive: Duration(minutes: 5),
            retryPolicy: RetryPolicy.immediate(maxRetries: 2),
          ),
          fetch: (param) async {
            fetchCount++;
            if (fetchCount < 3) {
              throw StateError('Transient API failure $fetchCount');
            }
            return 'Recovered data';
          },
        );

        final result = await query.get(const ());
        expect(result, 'Recovered data');
        expect(fetchCount, 3);
        expect(query.currentData(), 'Recovered data');

        await query.dispose();
      },
    );
  });
}
