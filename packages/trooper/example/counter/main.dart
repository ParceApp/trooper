import 'dart:async';
import 'package:trooper/trooper.dart';

/// Minimalist counter controller managing in-memory reactive state.
class CounterController extends TrooperController {
  // Local state container initialized to 0
  late final count = local<int, ()>(
    namespace: 'counter_value',
    initialValue: 0,
  );

  /// Increments the counter by 1.
  void increment() {
    count.update((val) => val + 1, const ());
  }

  /// Decrements the counter by 1.
  void decrement() {
    count.update((val) => val - 1, const ());
  }

  /// Resets the counter back to its initial value (0).
  void reset() {
    count.reset(const ());
  }
}

void main() async {
  print('====================================================');
  print('              TROOPER COUNTER EXAMPLE               ');
  print('====================================================\n');

  final controller = CounterController();
  await controller.initialize();

  // Watch state updates reactively
  final subscription = controller.count.watch(const ()).listen((state) {
    if (state case DataLoaded(:final data)) {
      print('Current Count: $data');
    }
  });

  // Allow subscription to attach
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('1. Incrementing...');
  controller.increment();
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('2. Incrementing again...');
  controller.increment();
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('3. Decrementing...');
  controller.decrement();
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('4. Resetting to initial value...');
  controller.reset();
  await Future<void>.delayed(const Duration(milliseconds: 10));

  print('\nSynchronous read via currentData: ${controller.count.currentData(const ())}');

  // Clean disposal
  await subscription.cancel();
  await controller.dispose();
  print('CounterController disposed cleanly.');
  print('====================================================');
}
