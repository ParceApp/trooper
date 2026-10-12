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
      expect(controller.userQuery.currentData(), 'User');

      controller.invalidate();

      expect(externalInvalidated, isTrue);
      expect(controller.userQuery.current(), isA<DataInitial<String>>());

      await controller.dispose();
    });

    test('controller factory methods create and manage all Trooper types', () async {
      final controller = _FullFactoryController();

      await controller.initialize();
      expect(controller.initCalled, isTrue);

      // Local & KeyedLocal
      expect(controller.theme.current().dataOrNull, 'dark');
      controller.theme.set('light', const ());
      expect(controller.theme.current().dataOrNull, 'light');

      controller.featureFlags.setKey('beta', true, const ());
      expect(controller.featureFlags.currentKeyData('beta'), isTrue);

      // Mutation
      final mutationResult = await controller.createPost.execute((title: 'Hello world'));
      expect(mutationResult, 'Created: Hello world');

      // Hooks
      controller.pause();
      expect(controller.pauseCalled, isTrue);

      controller.resume();
      expect(controller.resumeCalled, isTrue);

      controller.recover();
      expect(controller.recoverCalled, isTrue);

      controller.didChangeDependencies();
      expect(controller.depsCalled, isTrue);

      // Manage and unregister
      final dummyInvalidatable = _TestInvalidatable(() {});
      controller.manageAll([dummyInvalidatable]);
      expect(controller.unregister(dummyInvalidatable), isTrue);

      await controller.dispose();
      expect(controller.disposeCalled, isTrue);

      // Attempting to manage after disposal throws StateError
      expect(
        () => controller.manage(_TestInvalidatable(() {})),
        throwsA(isA<StateError>()),
      );
    });

    test('controller cancellable query factory, defaultStorage, and extraLifecycleChildren', () async {
      final storage = InMemoryStorageBackend();
      final externalService = _TestLifecycleService();

      final controller = _FullFeaturedController(
        storage: storage,
        externalLifecycle: externalService,
      );

      // Access late fields so they are instantiated and managed
      controller.cancellableQ;
      controller.cancellableKQ;

      expect(controller.managedCount, greaterThan(0));
      expect(controller.managedChildren.isNotEmpty, isTrue);
      expect(controller.managedInvalidatables.isNotEmpty, isTrue);

      await controller.initialize();
      expect(externalService.initCalled, isTrue);

      final queryResult = await controller.cancellableQ.get(const ());
      expect(queryResult, 'Cancellable OK');

      final keyedResult = await controller.cancellableKQ.getKey(1, const ());
      expect(keyedResult, 'Keyed 1 OK');

      await controller.pause();
      expect(externalService.pauseCalled, isTrue);

      await controller.resume();
      expect(externalService.resumeCalled, isTrue);

      await controller.dispose();
      expect(externalService.disposeCalled, isTrue);
    });
  });
}

class _TestLifecycleService with LifecycleAware {
  bool initCalled = false;
  bool pauseCalled = false;
  bool resumeCalled = false;
  bool disposeCalled = false;

  @override
  void initialize() => initCalled = true;

  @override
  void pause() => pauseCalled = true;

  @override
  void resume() => resumeCalled = true;

  @override
  void dispose() => disposeCalled = true;
}

class _FullFeaturedController extends TrooperController {
  _FullFeaturedController({
    required StorageBackend storage,
    required this.externalLifecycle,
  }) : super(defaultStorage: storage);

  final _TestLifecycleService externalLifecycle;

  late final cancellableQ = query<String, ()>(
    namespace: 'cancellable_q',
    cancellableFetch: (_, token) async => 'Cancellable OK',
  );

  late final cancellableKQ = keyedQuery<int, String, ()>(
    namespace: 'cancellable_kq',
    cancellableFetch: (id, _, token) async => 'Keyed $id OK',
  );

  @override
  List<LifecycleAware> get extraLifecycleChildren => [externalLifecycle];
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

class _FullFactoryController extends TrooperController {
  bool initCalled = false;
  bool pauseCalled = false;
  bool resumeCalled = false;
  bool recoverCalled = false;
  bool depsCalled = false;
  bool disposeCalled = false;

  late final theme = local<String, ()>(
    namespace: 'theme_local',
    initialValue: 'dark',
  );

  late final featureFlags = keyedLocal<String, bool, ()>(
    namespace: 'flags_local',
    initialValue: false,
  );

  late final clock = stream<DateTime, ()>(
    namespace: 'clock_stream',
    streamFactory: (_, _) => Stream.periodic(
      const Duration(hours: 1),
      (_) => DateTime.now(),
    ),
  );

  late final liveRoom = keyedStream<String, String, ()>(
    namespace: 'rooms_stream',
    streamFactory: (r, _, _) => Stream.value('welcome to $r'),
  );

  late final createPost = mutation<String, ({String title})>(
    namespace: 'create_post',
    action: (p) async => 'Created: ${p.title}',
  );

  @override
  void onInit() => initCalled = true;

  @override
  void onPause() => pauseCalled = true;

  @override
  void onResume() => resumeCalled = true;

  @override
  void onRecover() => recoverCalled = true;

  @override
  void onDependenciesChanged() => depsCalled = true;

  @override
  void onDispose() => disposeCalled = true;
}
