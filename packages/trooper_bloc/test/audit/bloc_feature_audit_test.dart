@Tags(['audit'])
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

class PairTubit extends Tubit<String> {
  PairTubit(this.a, this.b, {this.gate}) : super('init');

  final FakeAccessor<String, ()> a;
  final FakeAccessor<String, ()> b;
  final Future<void> Function()? gate;
  late final Watched<String> wa;
  late final Watched<String> wb;
  int derivations = 0;
  final reads = <(String?, String?)>[];

  @override
  List<Watched<Object?>> get sources => [wa = watch(a), wb = watch(b)];

  @override
  Future<MatchResult> matchSources(Emit<String> emit) async {
    derivations++;
    final before = wa.dataOrNull;
    if (gate != null) await gate!();
    final after = wa.dataOrNull;
    reads.add((before, after));
    emit('${wa.dataOrNull}+${wb.dataOrNull}');
    return MatchResult.handled;
  }

  @override
  void onAnyLoading(Emit<String> emit) => emit('loading');

  @override
  void onAnyError(Object error, StackTrace? st, Emit<String> emit) =>
      emit('error');
}

class _LoadedOnlyTubit extends Tubit<String> {
  _LoadedOnlyTubit(this.a) : super('init');
  final FakeAccessor<String, ()> a;
  late final Watched<String> w;

  @override
  List<Watched<Object?>> get sources => [w = watch(a)];

  @override
  MatchResult matchSources(Emit<String> emit) {
    if (w.state case DataLoaded(data: final d)) {
      emit('data:$d');
      return MatchResult.handled;
    }
    return MatchResult.unhandled;
  }

  @override
  void onAnyLoading(Emit<String> emit) => emit('loading');

  @override
  void onAnyError(Object error, StackTrace? st, Emit<String> emit) =>
      emit('error');
}

void main() {
  test('C-024 DataRefreshing keeps showing data, never the loading state',
      () async {
    final a = FakeAccessor<String, ()>(initialData: 'a1');
    final t = _LoadedOnlyTubit(a);
    await pumpEventQueue();
    final emitted = <String>[];
    final sub = t.stream.listen(emitted.add);
    a.emitRefreshing('a1');
    await pumpEventQueue();
    a.emitData('a2');
    await pumpEventQueue();
    expect(emitted, isNot(contains('loading')));
    expect(t.state, 'data:a2');
    await sub.cancel();
    await t.close();
  });

  test('FEAT-06 two updates in one event loop produce one derivation', () async {
    final a = FakeAccessor<String, ()>(initialData: 'a1');
    final b = FakeAccessor<String, ()>(initialData: 'b1');
    final t = PairTubit(a, b);
    await pumpEventQueue();
    final emitted = <String>[];
    final sub = t.stream.listen(emitted.add);
    t.derivations = 0;

    a.emitData('a2');
    b.emitData('b2');
    await pumpEventQueue();

    expect(t.derivations, 1);
    expect(emitted, ['a2+b2']);
    await sub.cancel();
    await t.close();
  });

  test('FEAT-06 snapshot is stable across an await inside matchSources', () async {
    final a = FakeAccessor<String, ()>(initialData: 'a1');
    final b = FakeAccessor<String, ()>(initialData: 'b1');
    late Completer<void> gate;
    final t = PairTubit(a, b, gate: () => (gate = Completer<void>()).future);
    await pumpEventQueue();
    // first derivation is waiting on its gate
    a.emitData('a2'); // live state changes while derivation is suspended
    await pumpEventQueue();
    final pending = gate;
    pending.complete();
    await pumpEventQueue();
    // complete every follow-up derivation
    for (var i = 0; i < 5 && !gate.isCompleted; i++) {
      gate.complete();
      await pumpEventQueue();
    }

    for (final (before, after) in t.reads) {
      expect(after, before, reason: 'snapshot changed within one derivation');
    }
    expect(t.state, 'a2+b1', reason: 'final state reflects latest sources');
    await t.close();
  });
}
