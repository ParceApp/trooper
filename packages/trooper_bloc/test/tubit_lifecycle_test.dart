import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

class _ItemTubit extends Tubit<String> {
  _ItemTubit(this.accessor) : super('init');
  final Accessor<String, ()> accessor;
  late final Watched<String> item;

  @override
  List<Watched<Object?>> get sources => [item = watch(accessor)];

  @override
  MatchResult matchSources(Emit<String> emit) {
    emit(item.dataOrNull ?? 'none');
    return MatchResult.handled;
  }

  @override
  void onAnyLoading(Emit<String> emit) => emit('loading');

  @override
  void onAnyError(Object error, StackTrace? st, Emit<String> emit) =>
      emit('error');
}

/// Accessor whose stream reports whether anyone listens.
final class _ListenTrackingAccessor implements Accessor<String, ()> {
  final _controller = StreamController<StatefulData<String>>.broadcast();

  bool get hasListeners => _controller.hasListener;

  Future<void> close() => _controller.close();

  @override
  StatefulStream<String> get stream =>
      StatefulStream<String>(_controller.stream, currentStateProvider: current);

  @override
  StatefulStream<String> watch({()? initialParameter, bool eager = false}) =>
      stream;

  @override
  Future<String> get(() parameter, {bool forceRefresh = false}) async => 'a';

  @override
  Future<String> refresh(() parameter) async => 'a';

  @override
  void trigger(() parameter, {bool forceRefresh = false}) {}

  @override
  StatefulData<String> current() => const DataLoaded('a');

  @override
  String? currentData() => 'a';

  @override
  void invalidate() {}
}

void main() {
  test('Tubit close cancels source subscriptions', () async {
    final source = _ListenTrackingAccessor();
    final t = _ItemTubit(source);
    await pumpEventQueue();
    expect(source.hasListeners, isTrue);
    await t.close();
    expect(source.hasListeners, isFalse);
    await source.close();
  });

  test('Tubit close is idempotent', () async {
    final t = _ItemTubit(FakeAccessor<String, ()>(initialData: 'a'));
    await pumpEventQueue();
    await t.close();
    await t.close();
  });
}
