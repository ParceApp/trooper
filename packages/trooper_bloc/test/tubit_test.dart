import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

sealed class TubitTestState {
  const TubitTestState();
}

final class TubitLoadingState extends TubitTestState {
  const TubitLoadingState();
}

final class TubitLoadedState extends TubitTestState {
  const TubitLoadedState(this.data);
  final String data;
}

final class TubitErrorState extends TubitTestState {
  const TubitErrorState(this.error);
  final Object error;
}

class CounterTubit extends Tubit<TubitTestState> {
  CounterTubit(this.accessor) : super(const TubitLoadingState());

  final FakeAccessor<String, ()> accessor;
  late final Watched<String> item;

  @override
  List<Watched<Object?>> get sources => [
    item = watch(accessor),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<TubitTestState> emit) {
    switch (item.state) {
      case DataLoaded(data: final d):
        emit(TubitLoadedState(d));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<TubitTestState> emit) => emit(const TubitLoadingState());

  @override
  void onAnyError(Object error, StackTrace? st, Emit<TubitTestState> emit) =>
      emit(TubitErrorState(error));

  Future<void> refresh() => accessor.refresh(const ());
}

void main() {
  group('Tubit', () {
    test('initializes and emits loaded state directly when warm', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'cubit_cached');
      final tubit = CounterTubit(fake);

      await pumpEventQueue();

      expect(tubit.state, isA<TubitLoadedState>());
      expect((tubit.state as TubitLoadedState).data, 'cubit_cached');

      await tubit.close();
    });

    test('transitions through loading and error fallbacks', () async {
      final fake = FakeAccessor<String, ()>();
      final tubit = CounterTubit(fake);

      await pumpEventQueue();
      expect(tubit.state, isA<TubitLoadingState>());

      fake.emitData('loaded_value');
      await pumpEventQueue();
      expect((tubit.state as TubitLoadedState).data, 'loaded_value');

      fake.emitError('failure');
      await pumpEventQueue();
      expect((tubit.state as TubitErrorState).error, 'failure');

      await tubit.close();
    });

    test('refresh invokes refresh on accessor', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'init');
      final tubit = CounterTubit(fake);
      await pumpEventQueue();

      await tubit.refresh();
      expect(fake.refreshCount, 1);

      await tubit.close();
    });

    test('pause and resume lifecycle controls source stream updates in Tubit', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'v1');
      final tubit = CounterTubit(fake);
      await pumpEventQueue();

      expect((tubit.state as TubitLoadedState).data, 'v1');

      tubit.pause();
      fake.emitData('v2_paused');
      await pumpEventQueue();

      expect((tubit.state as TubitLoadedState).data, 'v1');

      tubit.resume();
      await pumpEventQueue();

      expect((tubit.state as TubitLoadedState).data, 'v2_paused');

      await tubit.close();
    });

    test('matchSources exception in Tubit routes to onAnyError and onError', () async {
      final fake = FakeAccessor<String, ()>(initialData: 'ok');
      final tubit = ThrowingTubit(fake);
      await pumpEventQueue();

      expect(tubit.state, isA<TubitErrorState>());
      expect((tubit.state as TubitErrorState).error, 'Cubit derivation exploded');
      expect(tubit.capturedError, 'Cubit derivation exploded');

      await tubit.close();
    });
  });
}

class ThrowingTubit extends Tubit<TubitTestState> {
  ThrowingTubit(this.accessor) : super(const TubitLoadingState());

  final FakeAccessor<String, ()> accessor;
  Object? capturedError;

  @override
  List<Watched<Object?>> get sources => [watch(accessor)];

  @override
  MatchResult matchSources(Emit<TubitTestState> emit) {
    throw 'Cubit derivation exploded';
  }

  @override
  void onAnyError(Object error, StackTrace? st, Emit<TubitTestState> emit) {
    emit(TubitErrorState(error));
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    capturedError = error;
    super.onError(error, stackTrace);
  }
}
