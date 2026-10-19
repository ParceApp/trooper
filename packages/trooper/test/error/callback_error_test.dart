import 'dart:async';

import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

/// Runs [body] in a guarded zone and returns every uncaught error.
Future<List<Object>> zoneErrors(Future<void> Function() body) async {
  final errors = <Object>[];
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await body();
      await pumpEventQueue();
    } finally {
      done.complete();
    }
  }, (e, _) => errors.add(e));
  await done.future;
  return errors;
}

class _Target implements Invalidatable {
  _Target({this.fail = false});
  final bool fail;
  int calls = 0;

  @override
  void invalidate() {
    calls++;
    if (fail) throw StateError('target bug');
  }
}

class _Controller extends TrooperController {
  _Controller(this.targets);
  final List<Invalidatable> targets;

  @override
  List<Invalidatable> get extraInvalidatables => targets;
}

Matcher _stateError(String message) =>
    contains(isA<StateError>().having((e) => e.message, 'message', message));

void main() {
  test('async side effect failure reaches the zone', () async {
    String? result;
    final errors = await zoneErrors(() async {
      final q = QueryTrooper<String, ()>(
        namespace: 'cb_async',
        fetch: (_) async => 'v',
        sideEffects: TrooperSideEffects(
          onData: (_, _) async => throw StateError('async bug'),
        ),
      );
      result = await q.get(());
      await q.dispose();
    });
    expect(result, 'v');
    expect(errors, _stateError('async bug'));
  });

  test('keyed side effect failure reaches the zone', () async {
    final errors = await zoneErrors(() async {
      final q = KeyedQueryTrooper<String, String, ()>(
        namespace: 'cb_keyed',
        fetch: (_, _) async => 'v',
        sideEffects: KeyedTrooperSideEffects(
          onData: (_, _, _) => throw StateError('keyed bug'),
        ),
      );
      await q.getKey('a', ());
      await q.dispose();
    });
    expect(errors, _stateError('keyed bug'));
  });

  test('mutation onSuccess failure reaches the zone, result is kept', () async {
    String? result;
    final errors = await zoneErrors(() async {
      final m = TrooperMutation<String, ()>(
        namespace: 'cb_mut',
        action: (_) async => 'saved',
        sideEffects: TrooperMutationSideEffects(
          onSuccess: (_, _) => throw StateError('navigation bug'),
        ),
      );
      result = await m.execute(());
      await m.dispose();
    });
    expect(result, 'saved');
    expect(errors, _stateError('navigation bug'));
  });

  test('failing cancel listener reaches the zone, others still run', () async {
    var secondRan = false;
    final errors = await zoneErrors(() async {
      final token = TrooperCancelToken()
        ..onCancel(() => throw StateError('listener bug'))
        ..onCancel(() => secondRan = true);
      token.cancel();
      token.onCancel(() => throw StateError('late listener bug'));
    });
    expect(secondRan, isTrue);
    expect(errors, _stateError('listener bug'));
    expect(errors, _stateError('late listener bug'));
  });

  test(
    'failing invalidate target reaches the zone, others still run',
    () async {
      final ok = _Target();
      final errors = await zoneErrors(() async {
        final controller = _Controller([_Target(fail: true), ok]);
        controller.invalidate();
        await controller.dispose();
      });
      expect(ok.calls, 1);
      expect(errors, _stateError('target bug'));
    },
  );
}
