@Tags(['audit'])
library;

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

void main() {
  test('LIFE-02 Tubit close cancels source subscriptions', () async {
    final ctrl = StatefulStreamController<String>();
    final q = QueryTrooper<String, ()>(
      namespace: 'b_l02',
      fetch: (_) async => 'a',
      streamController: ctrl,
    );
    final t = _ItemTubit(q());
    await pumpEventQueue();
    expect(ctrl.hasListeners, isTrue);
    await t.close();
    expect(ctrl.hasListeners, isFalse);
    await q.dispose();
  });

  test('LIFE-01 Tubit close is idempotent', () async {
    final t = _ItemTubit(FakeAccessor<String, ()>(initialData: 'a'));
    await pumpEventQueue();
    await t.close();
    await t.close();
  });
}
