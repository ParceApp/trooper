import 'dart:math' as math;

/// Defines an automated retry strategy for queries and network operations.
///
/// Configures the maximum number of retry attempts, backoff timing,
/// and an optional predicate to filter which exceptions trigger a retry.
///
/// ### Example:
/// ```dart
/// final config = TrooperConfig(
///   retryPolicy: RetryPolicy.exponential(
///     maxRetries: 3,
///     initialDelay: const Duration(milliseconds: 300),
///   ),
/// );
/// ```
class RetryPolicy {
  /// Creates a custom [RetryPolicy].
  const RetryPolicy({
    this.maxRetries = 3,
    this.delay = const Duration(milliseconds: 500),
    this.backoffMultiplier = 1.0,
    this.maxDelay,
    this.retryWhen,
    this.jitter = defaultJitter,
  }) : assert(maxRetries >= 0, 'maxRetries must be non-negative'),
       assert(backoffMultiplier >= 1.0, 'backoffMultiplier must be >= 1.0'),
       assert(jitter >= 0.0 && jitter <= 1.0, 'jitter must be in [0, 1]');

  /// No-op retry policy that never retries failed operations.
  const RetryPolicy.none()
    : maxRetries = 0,
      delay = Duration.zero,
      backoffMultiplier = 1.0,
      maxDelay = null,
      retryWhen = null,
      jitter = 0.0;

  /// Retries immediately without delay up to [maxRetries] times.
  const RetryPolicy.immediate({
    int maxRetries = 3,
    bool Function(Object error)? retryWhen,
  }) : this(
         maxRetries: maxRetries,
         delay: Duration.zero,
         backoffMultiplier: 1.0,
         maxDelay: null,
         retryWhen: retryWhen,
         jitter: 0.0,
       );

  /// Retries with a fixed [delay] between attempts.
  const RetryPolicy.linear({
    int maxRetries = 3,
    Duration delay = const Duration(milliseconds: 500),
    Duration? maxDelay,
    bool Function(Object error)? retryWhen,
    double jitter = defaultJitter,
  }) : this(
         maxRetries: maxRetries,
         delay: delay,
         backoffMultiplier: 1.0,
         maxDelay: maxDelay,
         retryWhen: retryWhen,
         jitter: jitter,
       );

  /// Retries with exponential backoff increasing by [backoffMultiplier] on each attempt.
  const RetryPolicy.exponential({
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 250),
    double backoffMultiplier = 2.0,
    Duration? maxDelay,
    bool Function(Object error)? retryWhen,
    double jitter = defaultJitter,
  }) : this(
         maxRetries: maxRetries,
         delay: initialDelay,
         backoffMultiplier: backoffMultiplier,
         maxDelay: maxDelay,
         retryWhen: retryWhen,
         jitter: jitter,
       );

  /// The maximum number of retry attempts after the initial failure.
  final int maxRetries;

  /// The base delay duration between retries.
  final Duration delay;

  /// Multiplier applied to [delay] for each subsequent retry attempt.
  final double backoffMultiplier;

  /// Optional maximum upper bound for the delay duration.
  final Duration? maxDelay;

  /// Optional predicate determining whether a specific error should be retried.
  ///
  /// If `null`, all non-cancellation errors are retried.
  final bool Function(Object error)? retryWhen;

  /// Default share of each delay that is randomized, see [jitter].
  static const double defaultJitter = 0.5;

  static final math.Random _random = math.Random();

  /// Share of each delay that is randomized, between `0.0` and `1.0`.
  ///
  /// Each delay is drawn uniformly from `[d * (1 - jitter), d]`, where `d` is
  /// the backoff delay after the [maxDelay] cap, so clients that failed
  /// together do not retry in lockstep (thundering herd). [maxDelay] stays
  /// the upper bound. Defaults to [defaultJitter]; use `0.0` for exact,
  /// deterministic delays (e.g. in tests).
  final double jitter;

  /// Whether retries are enabled (`maxRetries > 0`).
  bool get isEnabled => maxRetries > 0;

  /// Calculates the backoff delay duration for a 1-based [attempt] index,
  /// randomized by [jitter].
  Duration delayForAttempt(int attempt) {
    final base = _backoffDelay(attempt);
    if (jitter == 0.0 || base == Duration.zero) return base;
    final spread = 1.0 - jitter * _random.nextDouble();
    return Duration(microseconds: (base.inMicroseconds * spread).round());
  }

  Duration _backoffDelay(int attempt) {
    if (attempt <= 1 || backoffMultiplier == 1.0 || delay == Duration.zero) {
      if (maxDelay != null && delay > maxDelay!) return maxDelay!;
      return delay;
    }
    final factor = math.pow(backoffMultiplier, attempt - 1).toDouble();
    final calculated = Duration(
      milliseconds: (delay.inMilliseconds * factor).round(),
    );
    if (maxDelay != null && calculated > maxDelay!) {
      return maxDelay!;
    }
    return calculated;
  }

  /// Determines whether [error] should be retried at the given 1-based [attempt].
  bool shouldRetry(Object error, int attempt) {
    if (attempt > maxRetries) return false;
    if (retryWhen != null) {
      return retryWhen!(error);
    }
    return true;
  }
}
