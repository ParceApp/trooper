import 'dart:async';

/// Test fixture simulating a push-based data source (e.g. WebSocket connection).
class MockStreamSource<T> {
  MockStreamSource({bool broadcast = true})
    : _controller = broadcast
          ? StreamController<T>.broadcast()
          : StreamController<T>();

  final StreamController<T> _controller;
  int subscriptionCount = 0;
  bool isClosed = false;

  Stream<T> get stream => _controller.stream;

  void emit(T data) {
    if (!isClosed) {
      _controller.add(data);
    }
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!isClosed) {
      _controller.addError(error, stackTrace);
    }
  }

  Future<void> close() async {
    isClosed = true;
    await _controller.close();
  }
}
