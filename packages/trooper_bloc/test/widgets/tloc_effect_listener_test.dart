import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

sealed class WidgetTestEvent extends TlocEvent {
  const WidgetTestEvent();
}

sealed class WidgetEffect {
  const WidgetEffect();
}

final class ShowSnackBarEffect extends WidgetEffect {
  const ShowSnackBarEffect(this.text);
  final String text;
}

class WidgetTestTloc extends Tloc<WidgetTestEvent, int>
    with Effects<WidgetEffect> {
  WidgetTestTloc() : super(0);

  final fake = FakeAccessor<int, ()>(initialData: 100);

  @override
  List<Watched<Object?>> get sources => [watch(fake)];

  @override
  MatchResult matchSources(Emit<int> emit) => .handled;

  @override
  void handlers() {}

  void triggerEffect(String text) => emitEffect(ShowSnackBarEffect(text));
}

void main() {
  group('TlocEffectListener', () {
    testWidgets('invokes onEffect with explicit bloc parameter', (tester) async {
      final bloc = WidgetTestTloc();
      final captured = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: TlocEffectListener<WidgetTestTloc, WidgetEffect>(
            bloc: bloc,
            onEffect: (context, effect) {
              if (effect is ShowSnackBarEffect) {
                captured.add(effect.text);
              }
            },
            child: const Text('Child Widget'),
          ),
        ),
      );

      expect(find.text('Child Widget'), findsOneWidget);
      expect(captured, isEmpty);

      bloc.triggerEffect('Toast Message 1');
      await tester.pump();

      expect(captured, ['Toast Message 1']);

      bloc.triggerEffect('Toast Message 2');
      await tester.pump();

      expect(captured, ['Toast Message 1', 'Toast Message 2']);

      await bloc.close();
    });

    testWidgets('resolves bloc from context.read when bloc parameter is omitted', (tester) async {
      final bloc = WidgetTestTloc();
      final captured = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: bloc,
            child: TlocEffectListener<WidgetTestTloc, WidgetEffect>(
              onEffect: (context, effect) {
                if (effect is ShowSnackBarEffect) {
                  captured.add(effect.text);
                }
              },
              child: const Text('Provided Child'),
            ),
          ),
        ),
      );

      expect(find.text('Provided Child'), findsOneWidget);

      bloc.triggerEffect('Context resolved!');
      await tester.pump();

      expect(captured, ['Context resolved!']);

      await bloc.close();
    });

    testWidgets('filters effects when listenWhen is provided', (tester) async {
      final bloc = WidgetTestTloc();
      final captured = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: TlocEffectListener<WidgetTestTloc, WidgetEffect>(
            bloc: bloc,
            listenWhen: (effect) =>
                effect is ShowSnackBarEffect && effect.text.startsWith('Allow'),
            onEffect: (context, effect) {
              if (effect is ShowSnackBarEffect) {
                captured.add(effect.text);
              }
            },
            child: const Text('Filtered Child'),
          ),
        ),
      );

      bloc.triggerEffect('Ignore this');
      await tester.pump();
      expect(captured, isEmpty);

      bloc.triggerEffect('Allow this');
      await tester.pump();
      expect(captured, ['Allow this']);

      await bloc.close();
    });

    testWidgets('resubscribes when widget.bloc instance changes', (tester) async {
      final bloc1 = WidgetTestTloc();
      final bloc2 = WidgetTestTloc();
      final captured = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: TlocEffectListener<WidgetTestTloc, WidgetEffect>(
            bloc: bloc1,
            onEffect: (context, effect) {
              if (effect is ShowSnackBarEffect) {
                captured.add(effect.text);
              }
            },
            child: const Text('Dynamic Bloc Child'),
          ),
        ),
      );

      bloc1.triggerEffect('from bloc1');
      await tester.pump();
      expect(captured, ['from bloc1']);

      // Rebuild with bloc2
      await tester.pumpWidget(
        MaterialApp(
          home: TlocEffectListener<WidgetTestTloc, WidgetEffect>(
            bloc: bloc2,
            onEffect: (context, effect) {
              if (effect is ShowSnackBarEffect) {
                captured.add(effect.text);
              }
            },
            child: const Text('Dynamic Bloc Child'),
          ),
        ),
      );

      bloc2.triggerEffect('from bloc2');
      await tester.pump();
      expect(captured, ['from bloc1', 'from bloc2']);

      await bloc1.close();
      await bloc2.close();
    });
  });
}
