import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

final class DummyEvent extends TlocEvent {
  const DummyEvent();
}

void main() {
  group('FakeAccessor', () {
    test('current and currentData reflect internal state', () {
      final fake = FakeAccessor<String, ()>(initialData: 'test');
      expect(fake.current().dataOrNull, 'test');
      expect(fake.currentData(), 'test');
    });

    test('get returns data when available and throws when empty', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'available');
      final result = await fake.get(const ());
      expect(result, 'available');
      expect(fake.getCount, 1);

      fake.invalidate();
      expect(fake.invalidateCount, 1);
      expect(fake.current(), isA<DataInitial<String>>());
      expect(() => fake.get(const ()), throwsStateError);
    });

    test('refresh throws when data is empty', () async {
      final fake = FakeAccessor<String, ()>();
      expect(() => fake.refresh(const ()), throwsStateError);
      expect(fake.refreshCount, 1);
    });

    test('trigger increments counter', () {
      final fake = FakeAccessor<String, ()>();
      fake.trigger(const ());
      expect(fake.triggerCount, 1);
    });

    test('emitLoading and emitRefreshing update state and stream', () async {
      final fake = FakeAccessor<String, ()>();
      final states = <StatefulData<String>>[];
      final stream = fake.watch();
      expect(stream.currentState, isA<DataInitial<String>>());
      final sub = stream.listen(states.add);

      fake.emitLoading(progress: 0.5);
      fake.emitRefreshing('data', progress: 0.8);
      await pumpEventQueue();

      expect(states.length, 2);
      expect(states[0].isLoading, isTrue);
      expect(states[1].isRefreshing, isTrue);

      await sub.cancel();
      await fake.close();
    });
  });

  group('TlocEvent', () {
    test('instantiates const constructor', () {
      const event = DummyEvent();
      expect(event, isA<TlocEvent>());
    });
  });
}
