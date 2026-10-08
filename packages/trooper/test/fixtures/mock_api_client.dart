import 'dart:async';
import 'package:trooper/trooper.dart';

/// Test fixture simulating an asynchronous API client with latency, cancellation, and error injection.
class MockApiClient<P, T> {
  MockApiClient({
    this.defaultResponse,
    this.latency,
  });

  T? defaultResponse;
  Duration? latency;

  int callCount = 0;
  P? lastParameter;
  TrooperCancelToken? lastCancelToken;
  bool wasCancelled = false;

  Object? failureError;
  Completer<T>? deferredCompleter;

  Future<T> fetch(P param, [TrooperCancelToken? cancelToken]) async {
    callCount++;
    lastParameter = param;
    lastCancelToken = cancelToken;

    cancelToken?.onCancel(() {
      wasCancelled = true;
    });

    if (failureError != null) {
      final err = failureError!;
      failureError = null;
      throw err;
    }

    if (deferredCompleter != null) {
      return deferredCompleter!.future;
    }

    if (latency != null) {
      await Future<void>.delayed(latency!);
    }

    if (cancelToken != null && cancelToken.isCancelled) {
      throw const TrooperCancelledException(message: 'Request was cancelled');
    }

    if (defaultResponse != null) {
      return defaultResponse!;
    }

    throw StateError('No default response or deferred completer configured');
  }

  void completeDeferred(T value) {
    deferredCompleter?.complete(value);
    deferredCompleter = null;
  }

  void completeDeferredError(Object error, [StackTrace? stackTrace]) {
    deferredCompleter?.completeError(error, stackTrace);
    deferredCompleter = null;
  }

  void reset() {
    callCount = 0;
    lastParameter = null;
    lastCancelToken = null;
    wasCancelled = false;
    failureError = null;
    deferredCompleter = null;
  }
}
