import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

sealed class EffectTestEvent extends TlocEvent {
  const EffectTestEvent();
}

sealed class MyEffect {
  const MyEffect();
}

final class ShowToastEffect extends MyEffect {
  const ShowToastEffect(this.message);
  final String message;
}

class EffectTloc extends Tloc<EffectTestEvent, int> with Effects<MyEffect> {
  EffectTloc() : super(0);

  final fake = FakeAccessor<int, ()>(initialData: 1);

  @override
  List<Watched<Object?>> get sources => [watch(fake)];

  @override
  MatchResult matchSources(Emit<int> emit) => .handled;

  @override
  void handlers() {}

  void triggerEffect(String msg) => emitEffect(ShowToastEffect(msg));
}

void main() {
  group('Effects mixin', () {
    test('emits one-off effects to effect stream', () async {
      final bloc = EffectTloc();
      final emittedEffects = <MyEffect>[];

      final sub = bloc.effects.listen(emittedEffects.add);

      bloc.triggerEffect('Hello 1');
      bloc.triggerEffect('Hello 2');
      await pumpEventQueue();

      expect(emittedEffects.length, 2);
      expect((emittedEffects[0] as ShowToastEffect).message, 'Hello 1');
      expect((emittedEffects[1] as ShowToastEffect).message, 'Hello 2');

      await sub.cancel();
      await bloc.close();

      // Emitting on closed bloc is safely ignored
      bloc.triggerEffect('Ignored');
      await pumpEventQueue();
      expect(emittedEffects.length, 2);
    });
  });
}
