import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

const _global = TrooperConfig(timeToLive: Duration(seconds: 42));
const _controllerDefault = TrooperConfig(timeToLive: Duration(seconds: 7));
const _own = TrooperConfig(timeToLive: Duration(seconds: 3));

class _Controller extends TrooperController {
  _Controller({super.defaultConfig});

  late final withOwnConfig = query<String, ()>(
    namespace: 'gd_own',
    fetch: (_) async => 'v',
    config: _own,
  );

  late final withoutConfig = query<String, ()>(
    namespace: 'gd_none',
    fetch: (_) async => 'v',
  );
}

void main() {
  setUp(TrooperConfig.resetDefault);
  tearDown(TrooperConfig.resetDefault);

  group('TrooperConfig global default', () {
    test('without setDefault, current is const TrooperConfig()', () async {
      expect(TrooperConfig.current.timeToLive, const Duration(minutes: 1));
      final q = QueryTrooper<String, ()>(
        namespace: 'gd_fallback',
        fetch: (_) async => 'v',
      );
      expect(q.config.timeToLive, const Duration(minutes: 1));
      await q.dispose();
    });

    test(
      'a standalone trooper without config uses the global default',
      () async {
        TrooperConfig.setDefault(_global);
        expect(TrooperConfig.current, same(_global));
        final q = QueryTrooper<String, ()>(
          namespace: 'gd_standalone',
          fetch: (_) async => 'v',
        );
        final k = KeyedQueryTrooper<int, String, ()>(
          namespace: 'gd_standalone_k',
          fetch: (_, _) async => 'v',
        );
        expect(q.config, same(_global));
        expect(k.config, same(_global));
        await q.dispose();
        await k.dispose();
      },
    );

    test(
      'a controller without defaultConfig uses the global default',
      () async {
        TrooperConfig.setDefault(_global);
        final c = _Controller();
        expect(c.withoutConfig.config.timeToLive, _global.timeToLive);
        await c.dispose();
      },
    );

    test('the controller defaultConfig wins over the global default', () async {
      TrooperConfig.setDefault(_global);
      final c = _Controller(defaultConfig: _controllerDefault);
      expect(c.withoutConfig.config.timeToLive, _controllerDefault.timeToLive);
      await c.dispose();
    });

    test('the config of the trooper wins over everything else', () async {
      TrooperConfig.setDefault(_global);
      final c = _Controller(defaultConfig: _controllerDefault);
      expect(c.withOwnConfig.config.timeToLive, _own.timeToLive);
      await c.dispose();
    });

    test('setDefault throws a StateError after the first trooper', () async {
      final q = QueryTrooper<String, ()>(
        namespace: 'gd_locked',
        fetch: (_) async => 'v',
        config: _own,
      );
      expect(
        () => TrooperConfig.setDefault(_global),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('first trooper'), contains('main()')),
          ),
        ),
      );
      expect(TrooperConfig.current.timeToLive, const Duration(minutes: 1));
      await q.dispose();
    });

    test('a mutation also locks the default', () async {
      final m = TrooperMutation<String, ()>(
        namespace: 'gd_mutation',
        action: (_) async => 'v',
      );
      expect(() => TrooperConfig.setDefault(_global), throwsStateError);
      await m.dispose();
    });

    test('setDefault may be called repeatedly before the first trooper', () {
      TrooperConfig.setDefault(_controllerDefault);
      TrooperConfig.setDefault(_global);
      expect(TrooperConfig.current, same(_global));
    });

    test('resetDefault restores the default and lifts the lock', () async {
      TrooperConfig.setDefault(_global);
      final q = QueryTrooper<String, ()>(
        namespace: 'gd_reset',
        fetch: (_) async => 'v',
      );
      await q.dispose();

      TrooperConfig.resetDefault();
      expect(TrooperConfig.current.timeToLive, const Duration(minutes: 1));
      TrooperConfig.setDefault(_controllerDefault);
      expect(TrooperConfig.current, same(_controllerDefault));
    });
  });
}
