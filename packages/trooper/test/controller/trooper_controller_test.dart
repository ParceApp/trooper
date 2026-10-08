import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

class TestFeatureController extends TrooperController {
  TestFeatureController({
    super.defaultConfig,
    super.defaultCache,
    super.defaultQueryQueue,
    super.defaultTelemetry,
  });

  bool initHookCalled = false;
  bool pauseHookCalled = false;
  bool resumeHookCalled = false;
  bool recoverHookCalled = false;
  bool disposeHookCalled = false;

  late final userProfile = query<String, ({int id})>(
    namespace: 'user_profile',
    fetch: (param) async => 'User ${param.id}',
  );

  late final userNotes = keyedQuery<int, String, ()>(
    namespace: 'user_notes',
    fetch: (id, _) async => 'Note for $id',
  );

  late final activeTab = local<String, ()>(
    namespace: 'active_tab',
    initialValue: 'overview',
  );

  late final updateBio = mutation<String, ({String bio})>(
    namespace: 'update_bio',
    action: (param) async => param.bio,
    invalidateOnSuccess: [userProfile],
  );

  @override
  FutureOr<void> onInit() {
    initHookCalled = true;
  }

  @override
  FutureOr<void> onPause() {
    pauseHookCalled = true;
  }

  @override
  FutureOr<void> onResume() {
    resumeHookCalled = true;
  }

  @override
  FutureOr<void> onRecover() {
    recoverHookCalled = true;
  }

  @override
  FutureOr<void> onDispose() {
    disposeHookCalled = true;
  }
}

void main() {
  group('TrooperController', () {
    test('lifecycle hooks and automatic child management', () async {
      final controller = TestFeatureController();

      // Access attributes so lazy variables instantiate
      expect(controller.userProfile.namespace, 'user_profile');
      expect(controller.userNotes.namespace, 'user_notes');
      expect(controller.activeTab.namespace, 'active_tab');
      expect(controller.updateBio.namespace, 'update_bio');

      expect(controller.managedCount, 4);

      await controller.initialize();
      expect(controller.initHookCalled, isTrue);

      await controller.pause();
      expect(controller.pauseHookCalled, isTrue);

      await controller.resume();
      expect(controller.resumeHookCalled, isTrue);

      await controller.recover();
      expect(controller.recoverHookCalled, isTrue);

      await controller.dispose();
      expect(controller.disposeHookCalled, isTrue);
      expect(controller.isDisposed, isTrue);
    });

    test('service sharing: shared cache and queues are inherited by children',
        () async {
      final sharedCache = CacheStore();
      final sharedQueue = TrooperQueryQueue();
      final sharedTelemetry = TelemetryHub.isolated();

      final controller = TestFeatureController(
        defaultCache: sharedCache,
        defaultQueryQueue: sharedQueue,
        defaultTelemetry: sharedTelemetry,
      );

      // Verify that children use the shared services
      expect(controller.userProfile.cache, same(sharedCache));
      expect(controller.userProfile.queryQueue, same(sharedQueue));
      expect(controller.userProfile.telemetry, same(sharedTelemetry));

      final data = await controller.userProfile.get((id: 42));
      expect(data, 'User 42');

      // Shared cache should contain the entry
      expect(
        sharedCache.get<String>(
          QueryKey(controller.userProfile.namespace, (id: 42)),
        ),
        'User 42',
      );

      await controller.dispose();
    });

    test('extraInvalidatables cascade when controller invalidate is called',
        () async {
      var externalInvalidated = false;
      final externalTarget = _TestInvalidatable(() {
        externalInvalidated = true;
      });

      final controller = _CascadingController(externalTarget);

      await controller.userQuery.get(const ());
      expect(controller.userQuery.currentData(const ()), 'User');

      controller.invalidate();

      expect(externalInvalidated, isTrue);
      expect(controller.userQuery.current(const ()), isA<DataInitial<String>>());

      await controller.dispose();
    });
  });
}

class _TestInvalidatable implements Invalidatable {
  _TestInvalidatable(this.onInvalidate);
  final void Function() onInvalidate;

  @override
  void invalidate() => onInvalidate();
}

class _CascadingController extends TrooperController {
  _CascadingController(this.extra);
  final Invalidatable extra;

  late final userQuery = query<String, ()>(
    namespace: 'cascade_user',
    fetch: (_) async => 'User',
  );

  @override
  List<Invalidatable> get extraInvalidatables => [extra];
}
