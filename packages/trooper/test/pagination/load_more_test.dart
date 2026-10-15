import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

typedef _Filter = ({String category});
typedef _PageParam = ({_Filter filter, int page});
typedef _Page = ({List<String> items, bool hasMore});

/// Fake paginated API returning one item per page.
class _PageApi {
  final List<_PageParam> calls = [];
  final Map<int, Completer<_Page>> pending = {};
  bool defer = false;
  Object? failNext;
  int lastPage = 3;

  Future<_Page> fetch(_PageParam param) {
    calls.add(param);
    final error = failNext;
    if (error != null) {
      failNext = null;
      return Future.error(error);
    }
    if (defer) {
      final completer = Completer<_Page>();
      pending[param.page] = completer;
      return completer.future;
    }
    return Future.value(page(param));
  }

  _Page page(_PageParam param) => (
    items: ['${param.filter.category}-${param.page}'],
    hasMore: param.page < lastPage,
  );
}

class _ArticleController extends TrooperController {
  _ArticleController(this.api);
  final _PageApi api;

  late final articlePage = query<_Page, _PageParam>(
    namespace: 'articles',
    fetch: api.fetch,
    config: const TrooperConfig.noCache(),
  );

  late final articleFeed = loadMore(
    source: articlePage,
    initialPageParam: 1,
    nextPageParam: (last, all) => last.hasMore ? all.length + 1 : null,
  );
}

void main() {
  group('LoadMore', () {
    late _PageApi api;
    late QueryTrooper<_Page, _PageParam> source;
    late LoadMore<_Page, _Filter, int> feed;

    setUp(() {
      api = _PageApi();
      source = QueryTrooper<_Page, _PageParam>(
        namespace: 'articles',
        fetch: api.fetch,
        config: const TrooperConfig.noCache(),
      );
      feed = LoadMore(
        source: source,
        initialPageParam: 1,
        nextPageParam: (last, all) => last.hasMore ? all.length + 1 : null,
      );
    });

    tearDown(() async {
      await feed.dispose();
      await source.dispose();
    });

    test('infers all type arguments from the source', () {
      final inferred = LoadMore(
        source: source,
        initialPageParam: 1,
        nextPageParam: (_Page last, all) => last.hasMore ? 2 : null,
      );
      expect(inferred, isA<LoadMore<_Page, _Filter, int>>());
      inferred.dispose();

      final controller = _ArticleController(api);
      expect(controller.articleFeed, isA<LoadMore<_Page, _Filter, int>>());
      controller.dispose();
    });

    test('loads the first page', () async {
      final states = <StatefulData<LoadMoreData<_Page, int>>>[];
      final sub = feed.stream.listen(states.add);

      final data = await feed.get((category: 'tech'));
      await pumpEventQueue();

      expect(data.pages.single.items, ['tech-1']);
      expect(data.pageParams, [1]);
      expect(data.hasNextPage, isTrue);
      expect(api.calls.single, (filter: (category: 'tech'), page: 1));
      expect(states, [
        isA<DataInitial<LoadMoreData<_Page, int>>>(),
        isA<DataLoading<LoadMoreData<_Page, int>>>(),
        isA<DataLoaded<LoadMoreData<_Page, int>>>(),
      ]);
      await sub.cancel();
    });

    test(
      'get with the same filter returns loaded pages without fetching',
      () async {
        await feed.get((category: 'tech'));
        await feed.fetchNextPage();
        api.calls.clear();

        final data = await feed.get((category: 'tech'));

        expect(data.pages, hasLength(2));
        expect(api.calls, isEmpty);
      },
    );

    test('fetchNextPage appends pages until the end is reached', () async {
      await feed.get((category: 'tech'));
      await feed.fetchNextPage();
      await feed.fetchNextPage();

      final data = feed.currentData()!;
      expect(data.pageParams, [1, 2, 3]);
      expect(
        LoadMoreData<List<String>, int>(
          pages: data.pages.map((p) => p.items).toList(),
          pageParams: data.pageParams,
        ).items,
        ['tech-1', 'tech-2', 'tech-3'],
      );
      expect(data.hasNextPage, isFalse);
      expect(feed.hasNextPage, isFalse);

      api.calls.clear();
      await feed.fetchNextPage();
      expect(api.calls, isEmpty);
    });

    test('fetchNextPage does nothing before the first page loaded', () async {
      await feed.fetchNextPage();
      expect(api.calls, isEmpty);
      expect(feed.current(), isA<DataInitial<LoadMoreData<_Page, int>>>());
    });

    test('concurrent fetchNextPage calls share one request', () async {
      await feed.get((category: 'tech'));
      api.defer = true;

      final first = feed.fetchNextPage();
      final second = feed.fetchNextPage();
      expect(feed.currentData()!.isFetchingNextPage, isTrue);
      expect(feed.current().isLoaded, isTrue);

      api.pending[2]!.complete(api.page((filter: (category: 'tech'), page: 2)));
      await Future.wait([first, second]);

      expect(api.calls.where((c) => c.page == 2), hasLength(1));
      expect(feed.currentData()!.pages, hasLength(2));
      expect(feed.currentData()!.isFetchingNextPage, isFalse);
    });

    test('next page error keeps pages and retryNextPage recovers', () async {
      await feed.get((category: 'tech'));
      api.failNext = StateError('offline');

      await feed.fetchNextPage();

      var data = feed.currentData()!;
      expect(feed.current().isLoaded, isTrue);
      expect(data.pages, hasLength(1));
      expect(data.isFetchingNextPage, isFalse);
      expect(data.nextPageError, isA<StateError>());

      // A plain fetchNextPage (e.g. from a scroll listener) does not retry.
      api.calls.clear();
      await feed.fetchNextPage();
      expect(api.calls, isEmpty);

      await feed.retryNextPage();
      data = feed.currentData()!;
      expect(data.pages, hasLength(2));
      expect(data.hasNextPageError, isFalse);
    });

    test('changing the filter resets the feed and drops late pages', () async {
      await feed.get((category: 'tech'));
      api.defer = true;
      final nextPage = feed.fetchNextPage();

      final reload = feed.get((category: 'sports'));
      expect(feed.current(), isA<DataLoading<LoadMoreData<_Page, int>>>());

      api.pending[2]!.complete(api.page((filter: (category: 'tech'), page: 2)));
      await nextPage;
      expect(feed.current(), isA<DataLoading<LoadMoreData<_Page, int>>>());

      api.pending[1]!.complete(
        api.page((filter: (category: 'sports'), page: 1)),
      );
      final data = await reload;

      expect(data.pages.single.items, ['sports-1']);
      expect(feed.currentData()!.pages.single.items, ['sports-1']);
    });

    test(
      'refresh reloads from the first page while showing old pages',
      () async {
        await feed.get((category: 'tech'));
        await feed.fetchNextPage();
        api.defer = true;

        final refreshing = feed.refresh((category: 'tech'));
        final state = feed.current();
        expect(state, isA<DataRefreshing<LoadMoreData<_Page, int>>>());
        expect(state.dataOrNull!.pages, hasLength(2));

        api.pending[1]!.complete(
          api.page((filter: (category: 'tech'), page: 1)),
        );
        final data = await refreshing;

        expect(data.pages, hasLength(1));
        expect(
          feed.current(),
          isNot(isA<DataRefreshing<LoadMoreData<_Page, int>>>()),
        );
      },
    );

    test('first page error emits DataError and recover retries', () async {
      api.failNext = StateError('offline');

      await expectLater(feed.get((category: 'tech')), throwsStateError);
      expect(feed.current().isError, isTrue);

      feed.recover();
      await pumpEventQueue();

      expect(feed.currentData()!.pages.single.items, ['tech-1']);
    });

    test('recover retries a failed next page', () async {
      await feed.get((category: 'tech'));
      api.failNext = StateError('offline');
      await feed.fetchNextPage();

      feed.recover();
      await pumpEventQueue();

      expect(feed.currentData()!.pages, hasLength(2));
    });

    test('source invalidation reloads the first page while listened', () async {
      final sub = feed.stream.listen((_) {});
      await feed.get((category: 'tech'));
      await feed.fetchNextPage();
      await pumpEventQueue();
      api.calls.clear();

      source.invalidate();
      await pumpEventQueue();

      expect(api.calls.single.page, 1);
      expect(feed.currentData()!.pages, hasLength(1));
      await sub.cancel();
    });

    test('source invalidation resets the feed without listeners', () async {
      await feed.get((category: 'tech'));
      await pumpEventQueue();
      api.calls.clear();

      source.invalidate();
      await pumpEventQueue();

      expect(api.calls, isEmpty);
      expect(feed.current(), isA<DataInitial<LoadMoreData<_Page, int>>>());
    });

    test('invalidate resets the feed and eager watch reloads it', () async {
      await feed.get((category: 'tech'));
      feed.invalidate();
      expect(feed.current(), isA<DataInitial<LoadMoreData<_Page, int>>>());

      feed.watch(initialParameter: (category: 'tech'), eager: true);
      await pumpEventQueue();

      expect(feed.currentData()!.pages, hasLength(1));
    });
  });

  group('LoadMore in a TrooperController', () {
    test('is invalidated and disposed with the controller', () async {
      final controller = _ArticleController(_PageApi());
      final feed = controller.articleFeed;
      await feed.get((category: 'tech'));

      controller.invalidate();
      expect(feed.current(), isA<DataInitial<LoadMoreData<_Page, int>>>());

      await controller.dispose();
      expect(feed.isDisposed, isTrue);
    });
  });

  group('Classic paging', () {
    test('noCache query fetches every page fresh', () async {
      final api = _PageApi();
      final pages = QueryTrooper<_Page, _PageParam>(
        namespace: 'articles',
        fetch: api.fetch,
        config: const TrooperConfig.noCache(),
      );

      await pages.get((filter: (category: 'tech'), page: 1));
      await pages.get((filter: (category: 'tech'), page: 2));
      await pages.get((filter: (category: 'tech'), page: 1));

      expect(api.calls.map((c) => c.page), [1, 2, 1]);
      await pages.dispose();
    });
  });
}
