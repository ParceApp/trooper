import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

// Test Event hierarchy
sealed class TestEvent extends TlocEvent {
  const TestEvent();
}

final class TestRefreshEvent extends TestEvent {
  const TestRefreshEvent();
}

final class TestSetCustomEvent extends TestEvent {
  const TestSetCustomEvent(this.value);
  final String value;
}

// Test State hierarchy
sealed class TestState {
  const TestState();
}

final class TestLoadingState extends TestState {
  const TestLoadingState();
}

final class TestLoadedState extends TestState {
  const TestLoadedState(this.data);
  final String data;
}

final class TestMultiLoadedState extends TestState {
  const TestMultiLoadedState(this.item1, this.item2);
  final String item1;
  final int item2;
}

final class TestErrorState extends TestState {
  const TestErrorState(this.error);
  final Object error;
}

// Test Tloc implementation
class SimpleTloc extends Tloc<TestEvent, TestState> {
  SimpleTloc(this.fakeAccessor) : super(const TestLoadingState());

  final FakeAccessor<String, ()> fakeAccessor;
  late final Watched<String> source;

  @override
  List<Watched<Object?>> get sources => [source = watch(fakeAccessor)];

  @override
  FutureOr<MatchResult> matchSources(Emit<TestState> emit) {
    switch (source.state) {
      case DataLoaded(data: final d):
        emit(TestLoadedState(d));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<TestState> emit) {
    emit(const TestLoadingState());
  }

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<TestState> emit) {
    emit(TestErrorState(error));
  }

  @override
  void handlers() {
    on<TestRefreshEvent>((_, _) => fakeAccessor.refresh(const ()));
    on<TestSetCustomEvent>((event, emit) => emit(TestLoadedState(event.value)));
  }
}

// Multi-source Tloc implementation
class MultiSourceTloc extends Tloc<TestEvent, TestState> {
  MultiSourceTloc({required this.accessorA, required this.accessorB})
    : super(const TestLoadingState());

  final FakeAccessor<String, ()> accessorA;
  final FakeAccessor<int, ()> accessorB;

  late final Watched<String> sourceA;
  late final Watched<int> sourceB;

  @override
  List<Watched<Object?>> get sources => [
    sourceA = watch(accessorA),
    sourceB = watch(accessorB),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<TestState> emit) {
    switch ((sourceA.state, sourceB.state)) {
      case (DataLoaded(data: final a), DataLoaded(data: final b)):
        emit(TestMultiLoadedState(a, b));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<TestState> emit) {
    emit(const TestLoadingState());
  }

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<TestState> emit) {
    emit(TestErrorState(error));
  }

  @override
  void handlers() {}
}

// Async Tloc with simulated latency
class AsyncTloc extends Tloc<TestEvent, TestState> {
  AsyncTloc(this.accessor) : super(const TestLoadingState());

  final FakeAccessor<String, ()> accessor;
  late final Watched<String> source;
  Completer<void>? barrier;
  final observedSnapshots = <String>[];

  @override
  List<Watched<Object?>> get sources => [source = watch(accessor)];

  @override
  Future<MatchResult> matchSources(Emit<TestState> emit) async {
    switch (source.state) {
      case DataLoaded(data: final d):
        if (barrier != null) {
          final b = barrier;
          barrier = null;
          await b!.future;
        }
        // Record what source.state evaluates to after the await:
        final current = source.state.dataOrNull;
        if (current != null) {
          observedSnapshots.add(current);
        }
        emit(TestLoadedState(d));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<TestState> emit) => emit(const TestLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<TestState> emit) =>
      emit(TestErrorState(error));

  @override
  void handlers() {}
}

void main() {
  group('Tloc', () {
    test(
      'initializes and emits loaded state when source has warm cache',
      () async {
        final fake = FakeAccessor<String, ()>(initialData: 'cached');
        final bloc = SimpleTloc(fake);

        // Microtask pump
        await pumpEventQueue();

        expect(bloc.state, isA<TestLoadedState>());
        expect((bloc.state as TestLoadedState).data, 'cached');

        await bloc.close();
      },
    );

    test(
      'emits loading fallback on cold start and updates when source resolves',
      () async {
        final fake = FakeAccessor<String, ()>(); // DataInitial
        final bloc = SimpleTloc(fake);

        await pumpEventQueue();
        expect(bloc.state, isA<TestLoadingState>());

        fake.emitData('fresh');
        await pumpEventQueue();

        expect(bloc.state, isA<TestLoadedState>());
        expect((bloc.state as TestLoadedState).data, 'fresh');

        await bloc.close();
      },
    );

    test('fallback cascade invokes onAnyError when source fails', () async {
      final fake = FakeAccessor<String, ()>();
      final bloc = SimpleTloc(fake);

      await pumpEventQueue();
      expect(bloc.state, isA<TestLoadingState>());

      fake.emitError('network-failure');
      await pumpEventQueue();

      expect(bloc.state, isA<TestErrorState>());
      expect((bloc.state as TestErrorState).error, 'network-failure');

      await bloc.close();
    });

    test('multi-source tloc matches when all sources resolve', () async {
      final fakeA = FakeAccessor<String, ()>(initialData: 'title');
      final fakeB = FakeAccessor<int, ()>(); // Cold
      final bloc = MultiSourceTloc(accessorA: fakeA, accessorB: fakeB);

      await pumpEventQueue();
      expect(bloc.state, isA<TestLoadingState>());

      fakeB.emitData(42);
      await pumpEventQueue();

      expect(bloc.state, isA<TestMultiLoadedState>());
      final s = bloc.state as TestMultiLoadedState;
      expect(s.item1, 'title');
      expect(s.item2, 42);

      await bloc.close();
    });

    test('SWR guarantee: DataRefreshing does not revert to loading', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'v1');
      final bloc = SimpleTloc(fake);

      await pumpEventQueue();
      expect(bloc.state, isA<TestLoadedState>());

      // Background SWR refresh
      fake.emitRefreshing('v1');
      await pumpEventQueue();

      // State remains TestLoadedState with existing data, NOT TestLoadingState!
      expect(bloc.state, isA<TestLoadedState>());
      expect((bloc.state as TestLoadedState).data, 'v1');

      fake.emitData('v2');
      await pumpEventQueue();
      expect((bloc.state as TestLoadedState).data, 'v2');

      await bloc.close();
    });

    test(
      'snapshot-locking preserves source.state across asynchronous await',
      () async {
        final fake = FakeAccessor<String, ()>(initialData: 'version_1');
        final bloc = AsyncTloc(fake);
        final barrier = Completer<void>();
        bloc.barrier = barrier;

        // Kick off derivation
        await pumpEventQueue();

        // While AsyncTloc is suspended awaiting barrier:
        // mutate source in background!
        fake.emitData('version_2_mutated');

        // Release barrier
        barrier.complete();
        await pumpEventQueue();

        // Inside matchSources after await, source.state was locked to 'version_1' for the first run,
        // and then re-derived with 'version_2_mutated'
        expect(bloc.observedSnapshots, ['version_1', 'version_2_mutated']);
        expect((bloc.state as TestLoadedState).data, 'version_2_mutated');

        await bloc.close();
      },
    );

    test('processes user events registered via handlers()', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'initial');
      final bloc = SimpleTloc(fake);
      await pumpEventQueue();

      bloc.add(const TestSetCustomEvent('custom_override'));
      await pumpEventQueue();

      expect((bloc.state as TestLoadedState).data, 'custom_override');

      bloc.add(const TestRefreshEvent());
      await pumpEventQueue();

      expect(fake.refreshCount, 1);

      await bloc.close();
    });

    test(
      'close disposes subscriptions without disposing the shared Accessor',
      () async {
        final fake = FakeAccessor<String, ()>(initialData: 'data');
        final bloc = SimpleTloc(fake);
        await pumpEventQueue();

        await bloc.close();
        expect(bloc.isClosed, isTrue);

        // Fake accessor is still functional
        expect(fake.currentData(), 'data');
      },
    );

    test('pause and resume lifecycle controls source stream updates', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'v1');
      final bloc = SimpleTloc(fake);
      await pumpEventQueue();

      expect((bloc.state as TestLoadedState).data, 'v1');

      bloc.pause();
      fake.emitData('v2_while_paused');
      await pumpEventQueue();

      // State did not change while paused
      expect((bloc.state as TestLoadedState).data, 'v1');

      bloc.resume();
      await pumpEventQueue();

      // State updated upon resume
      expect((bloc.state as TestLoadedState).data, 'v2_while_paused');

      await bloc.close();
    });

    test('rederive manually triggers matchSources evaluation', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'initial');
      final bloc = SimpleTloc(fake);
      await pumpEventQueue();

      bloc.add(const TestSetCustomEvent('overridden'));
      await pumpEventQueue();
      expect((bloc.state as TestLoadedState).data, 'overridden');

      // Manual rederive re-evaluates source snapshots
      bloc.rederive();
      await pumpEventQueue();
      expect((bloc.state as TestLoadedState).data, 'initial');

      await bloc.close();
    });

    test(
      'watch initializes parameterized accessor with initial parameter and receives subsequent background updates',
      () async {
        final fake = FakeAccessor<String, ({int id})>(initialData: 'first_id');
        final bloc = ParameterizedTloc(fake);
        await pumpEventQueue();

        expect((bloc.state as TestLoadedState).data, 'first_id');

        fake.emitData('second_id');
        await pumpEventQueue();

        expect((bloc.state as TestLoadedState).data, 'second_id');

        await bloc.close();
      },
    );

    test(
      'watch passively listens to parameterized accessor without initial parameter',
      () async {
        final fake = FakeAccessor<String, ({String query})>();
        final bloc = PassiveParameterizedTloc(fake);
        await pumpEventQueue();

        // Initially loading fallback
        expect(bloc.state, isA<TestLoadingState>());

        // Trigger a parameterized fetch or emission in the background
        fake.emitData('result_for_query');
        await pumpEventQueue();

        expect(bloc.state, isA<TestLoadedState>());
        expect((bloc.state as TestLoadedState).data, 'result_for_query');

        await bloc.close();
      },
    );

    test('matchSources exception invokes onAnyError and onError', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'ready');
      final bloc = ThrowingTloc(fake);
      await pumpEventQueue();

      expect(bloc.state, isA<TestErrorState>());
      expect(
        (bloc.state as TestErrorState).error,
        'Simulated derivation crash',
      );
      expect(bloc.capturedError, 'Simulated derivation crash');

      await bloc.close();
    });

    test(
      'uses default mixin implementations when optional methods are omitted',
      () async {
        final fakeLoading = FakeAccessor<String, ()>();
        final blocLoading = MinimalTloc(fake: fakeLoading);
        await pumpEventQueue();
        expect(blocLoading.state, 0);
        await blocLoading.close();

        final fakeError = FakeAccessor<String, ()>();
        fakeError.emitError('err');
        final blocError = MinimalTloc(fake: fakeError);
        await pumpEventQueue();
        expect(blocError.state, 0);
        await blocError.close();

        final bloc = EmptySourcesTloc();
        await pumpEventQueue();

        expect(bloc.state, 0);
        expect(bloc.sources, isEmpty);

        await bloc.close();
      },
    );

    test(
      'emit called outside handler dispatches internal event and triggers BlocObserver',
      () async {
        final observer = _TestObserver();
        Bloc.observer = observer;

        final bloc = HelperMethodTloc();
        await pumpEventQueue();

        // Call helper method that uses emit(...) directly
        bloc.setCustomViaHelper('from_helper');
        await pumpEventQueue();

        expect(bloc.state, isA<TestLoadedState>());
        expect((bloc.state as TestLoadedState).data, 'from_helper');

        // Verify BLoC pipeline was exercised
        expect(observer.events.whereType<TlocSourceUpdateEvent>(), isNotEmpty);
        expect(
          observer.transitions.any(
            (t) =>
                t.event is TlocSourceUpdateEvent &&
                t.nextState is TestLoadedState &&
                (t.nextState as TestLoadedState).data == 'from_helper',
          ),
          isTrue,
        );
        expect(
          observer.changes.any(
            (c) =>
                c.nextState is TestLoadedState &&
                (c.nextState as TestLoadedState).data == 'from_helper',
          ),
          isTrue,
        );

        // Verify domain events also go through normally
        bloc.add(const TestSetCustomEvent('from_domain_event'));
        await pumpEventQueue();

        expect((bloc.state as TestLoadedState).data, 'from_domain_event');
        expect(observer.events.whereType<TestSetCustomEvent>(), isNotEmpty);
        expect(
          observer.transitions.any((t) => t.event is TestSetCustomEvent),
          isTrue,
        );

        await bloc.close();
        Bloc.observer = const _DefaultBlocObserver();
      },
    );
  });
}

class _DefaultBlocObserver extends BlocObserver {
  const _DefaultBlocObserver();
}

class _TestObserver extends BlocObserver {
  final List<Object?> events = [];
  final List<Transition<dynamic, dynamic>> transitions = [];
  final List<Change<dynamic>> changes = [];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    transitions.add(transition);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    changes.add(change);
  }
}

class HelperMethodTloc extends Tloc<TestEvent, TestState> {
  HelperMethodTloc() : super(const TestLoadingState());

  void setCustomViaHelper(String data) {
    emit(TestLoadedState(data));
  }

  @override
  MatchResult matchSources(Emit<TestState> emit) => .unhandled;

  @override
  void handlers() {
    on<TestSetCustomEvent>((event, emit) => emit(TestLoadedState(event.value)));
  }

  @override
  List<Watched<Object?>> get sources => [];
}

class EmptySourcesTloc extends Tloc<TestEvent, int> {
  EmptySourcesTloc() : super(0);

  @override
  MatchResult matchSources(Emit<int> emit) => .unhandled;

  @override
  void handlers() {}

  @override
  List<Watched<Object?>> get sources => [];
}

class MinimalTloc extends Tloc<TestEvent, int> {
  MinimalTloc({this.fake}) : super(0);

  final FakeAccessor<String, ()>? fake;

  @override
  List<Watched<Object?>> get sources => [if (fake != null) watch(fake!)];

  @override
  MatchResult matchSources(Emit<int> emit) => .unhandled;

  @override
  void handlers() {}
}

class ParameterizedTloc extends Tloc<TestEvent, TestState> {
  ParameterizedTloc(this.accessor) : super(const TestLoadingState());

  final FakeAccessor<String, ({int id})> accessor;
  late final Watched<String> item;

  @override
  List<Watched<Object?>> get sources => [
    item = watch(accessor, initialParameter: (id: 1), eager: true),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<TestState> emit) {
    switch (item.state) {
      case DataLoaded(data: final d):
        emit(TestLoadedState(d));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<TestState> emit) => emit(const TestLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<TestState> emit) =>
      emit(TestErrorState(error));

  @override
  void handlers() {}
}

class PassiveParameterizedTloc extends Tloc<TestEvent, TestState> {
  PassiveParameterizedTloc(this.accessor) : super(const TestLoadingState());

  final FakeAccessor<String, ({String query})> accessor;
  late final Watched<String> item;

  @override
  List<Watched<Object?>> get sources => [item = watch(accessor)];

  @override
  FutureOr<MatchResult> matchSources(Emit<TestState> emit) {
    switch (item.state) {
      case DataLoaded(data: final d):
        emit(TestLoadedState(d));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<TestState> emit) => emit(const TestLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<TestState> emit) =>
      emit(TestErrorState(error));

  @override
  void handlers() {}
}

class ThrowingTloc extends Tloc<TestEvent, TestState> {
  ThrowingTloc(this.fakeAccessor) : super(const TestLoadingState());

  final FakeAccessor<String, ()> fakeAccessor;
  Object? capturedError;

  @override
  List<Watched<Object?>> get sources => [watch(fakeAccessor)];

  @override
  FutureOr<MatchResult> matchSources(Emit<TestState> emit) {
    throw 'Simulated derivation crash';
  }

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<TestState> emit) {
    emit(TestErrorState(error));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    capturedError = error;
    super.onError(error, stackTrace);
  }

  @override
  void handlers() {}
}
