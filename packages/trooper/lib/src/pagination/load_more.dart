import 'dart:async';
import 'package:meta/meta.dart';
import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream_controller.dart';
import 'package:trooper/types/parameter.dart';

/// Accumulated pages of a [LoadMore] feed, including the status of the next-page request.
///
/// The load-more status lives inside the data so the feed stays [DataLoaded] while
/// the next page is loading or has failed. The list remains visible and only the
/// footer (spinner or retry button) needs to react to [isFetchingNextPage] and [nextPageError].
@immutable
final class LoadMoreData<TPage, PP extends Object> {
  /// Creates a [LoadMoreData] snapshot.
  LoadMoreData({
    required List<TPage> pages,
    required List<PP> pageParams,
    this.nextPageParam,
    this.isFetchingNextPage = false,
    this.nextPageError,
    this.nextPageStackTrace,
  }) : pages = List.unmodifiable(pages),
       pageParams = List.unmodifiable(pageParams);

  /// All loaded pages in load order.
  final List<TPage> pages;

  /// The page parameter used to load each entry of [pages].
  final List<PP> pageParams;

  /// The parameter of the next page, or `null` if the last page was reached.
  final PP? nextPageParam;

  /// Whether a next-page request is currently in flight.
  final bool isFetchingNextPage;

  /// The error of the last failed next-page request, or `null`.
  final Object? nextPageError;

  /// The stack trace of [nextPageError], if available.
  final StackTrace? nextPageStackTrace;

  /// Whether another page can be loaded.
  bool get hasNextPage => nextPageParam != null;

  /// Whether the last next-page request failed.
  bool get hasNextPageError => nextPageError != null;

  /// Returns a copy with the given fields replaced.
  ///
  /// Set [clearNextPageError] to remove [nextPageError] and [nextPageStackTrace].
  LoadMoreData<TPage, PP> copyWith({
    bool? isFetchingNextPage,
    Object? nextPageError,
    StackTrace? nextPageStackTrace,
    bool clearNextPageError = false,
  }) => LoadMoreData<TPage, PP>(
    pages: pages,
    pageParams: pageParams,
    nextPageParam: nextPageParam,
    isFetchingNextPage: isFetchingNextPage ?? this.isFetchingNextPage,
    nextPageError: clearNextPageError
        ? null
        : (nextPageError ?? this.nextPageError),
    nextPageStackTrace: clearNextPageError
        ? null
        : (nextPageStackTrace ?? this.nextPageStackTrace),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadMoreData<TPage, PP> &&
          _listEquals(other.pages, pages) &&
          _listEquals(other.pageParams, pageParams) &&
          other.nextPageParam == nextPageParam &&
          other.isFetchingNextPage == isFetchingNextPage &&
          other.nextPageError == nextPageError;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(pages),
    Object.hashAll(pageParams),
    nextPageParam,
    isFetchingNextPage,
    nextPageError,
  );

  @override
  String toString() =>
      'LoadMoreData<$TPage, $PP>(pages: ${pages.length}, '
      'nextPageParam: $nextPageParam, isFetchingNextPage: $isFetchingNextPage, '
      'nextPageError: $nextPageError)';
}

bool _listEquals<E>(List<E> a, List<E> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Convenience accessors for feeds whose pages are plain lists.
extension LoadMoreItems<E, PP extends Object> on LoadMoreData<List<E>, PP> {
  /// All items of all loaded pages, flattened in load order.
  List<E> get items => [for (final page in pages) ...page];
}

/// Load-more (infinite scroll) decorator over an existing page query.
///
/// Wraps any [Accessor] whose parameter has the shape `({F filter, PP page})` and
/// accumulates its pages into a single [LoadMoreData]. Every page is fetched through
/// the wrapped source via [Accessor.refresh], so retry, timeout, deduplication,
/// cancellation, telemetry, and side effects of the source apply to each page.
///
/// - [F] is the feed filter (use `()` for an unfiltered feed).
/// - [PP] is the page parameter, for example an `int` page number or a cursor.
///
/// Consumers watch the [LoadMore] feed, not the wrapped source: the source only
/// holds the most recently requested page.
///
/// ### Example:
/// ```dart
/// class ArticleController extends TrooperController {
///   late final _articlePage =
///       query<Page<Article>, ({({String category}) filter, int page})>(
///         namespace: 'articles',
///         fetch: (p) => api.getArticles(category: p.filter.category, page: p.page),
///         config: const TrooperConfig.noCache(),
///       );
///
///   late final articleFeed = loadMore(
///     source: _articlePage,
///     initialPageParam: 1,
///     nextPageParam: (last, all) => last.hasMore ? all.length + 1 : null,
///   );
/// }
///
/// controller.articleFeed.watch(initialParameter: (category: 'tech'), eager: true);
/// controller.articleFeed.fetchNextPage(); // e.g. when scrolled near the end
/// ```
///
/// When the wrapped source is invalidated (for example by a mutation's
/// `invalidateOnSuccess`), the feed reloads its first page if it has listeners,
/// or resets to [DataInitial] otherwise.
class LoadMore<TPage, F extends Parameter, PP extends Object>
    with LifecycleAware
    implements Accessor<LoadMoreData<TPage, PP>, F> {
  /// Creates a [LoadMore] feed over [source].
  ///
  /// [nextPageParam] receives the last loaded page and all loaded pages and returns
  /// the parameter of the next page, or `null` if there are no more pages.
  LoadMore({
    required this.source,
    required this.initialPageParam,
    required this.nextPageParam,
  }) {
    _sourceSubscription = source.stream.listen(
      _onSourceState,
      onError: (Object _) {},
    );
  }

  /// The wrapped page query.
  final Accessor<TPage, ({F filter, PP page})> source;

  /// The page parameter of the first page.
  final PP initialPageParam;

  /// Resolves the next page parameter, returning `null` when the end is reached.
  final PP? Function(TPage lastPage, List<TPage> allPages) nextPageParam;

  final StatefulStreamController<LoadMoreData<TPage, PP>> _controller =
      StatefulStreamController<LoadMoreData<TPage, PP>>();
  late final StreamSubscription<StatefulData<TPage>> _sourceSubscription;

  F? _filter;
  int _generation = 0;
  Future<LoadMoreData<TPage, PP>>? _firstPageFuture;
  Future<void>? _nextPageFuture;
  Completer<void>? _nextPageDone;
  bool _sourceHadState = false;
  bool _isDisposed = false;

  /// Whether this feed has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether another page can be loaded.
  bool get hasNextPage => _controller.currentData?.hasNextPage ?? false;

  @override
  StatefulStream<LoadMoreData<TPage, PP>> get stream => _controller.stream;

  @override
  StatefulStream<LoadMoreData<TPage, PP>> watch({
    F? initialParameter,
    bool eager = false,
  }) {
    if (eager && initialParameter != null) {
      if (current() is DataInitial || _filter != initialParameter) {
        get(initialParameter).ignore();
      }
    }
    return _controller.stream;
  }

  /// Returns the loaded pages for [parameter].
  ///
  /// Returns the current pages if they were loaded for the same filter. A different
  /// filter or [forceRefresh] reloads the feed starting at the first page.
  @override
  Future<LoadMoreData<TPage, PP>> get(
    F parameter, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && _filter == parameter) {
      final pending = _firstPageFuture;
      if (pending != null) return pending;
      final data = _controller.currentData;
      if (data != null) return Future.value(data);
    }
    return _loadFirstPage(parameter);
  }

  /// Reloads the feed starting at the first page, keeping the current pages visible
  /// as [DataRefreshing] until the first page arrives.
  @override
  Future<LoadMoreData<TPage, PP>> refresh(F parameter) =>
      get(parameter, forceRefresh: true);

  @override
  void trigger(F parameter, {bool forceRefresh = false}) {
    get(parameter, forceRefresh: forceRefresh).ignore();
  }

  /// Loads the next page and appends it.
  ///
  /// Does nothing if no pages are loaded, the end was reached, the first page is
  /// reloading, or the last next-page request failed (use [retryNextPage]).
  /// Concurrent calls share the in-flight request. Never throws: failures are
  /// reported through [LoadMoreData.nextPageError]. Completes early, without
  /// appending, when the feed is reset (filter change, refresh or invalidate).
  Future<void> fetchNextPage() {
    final pending = _nextPageFuture;
    if (pending != null) return pending;

    final state = _controller.currentState;
    if (state is! DataLoaded<LoadMoreData<TPage, PP>> ||
        state is DataRefreshing<LoadMoreData<TPage, PP>>) {
      return Future.value();
    }
    final data = state.data;
    final pageParam = data.nextPageParam;
    final filter = _filter;
    if (pageParam == null || filter == null || data.hasNextPageError) {
      return Future.value();
    }

    final generation = _generation;
    _controller.emitData(
      data.copyWith(isFetchingNextPage: true, clearNextPageError: true),
    );
    // Completes when the page is applied or dropped, or when the feed resets,
    // whichever comes first, independent of the source's conflict policy.
    final done = _nextPageDone = Completer<void>();
    _fetchNextPage(filter, pageParam, generation).whenComplete(() {
      if (!done.isCompleted) done.complete();
    });
    return _nextPageFuture = done.future;
  }

  /// Clears a failed next-page request and loads the next page again.
  Future<void> retryNextPage() {
    final data = _controller.currentData;
    if (data != null && data.hasNextPageError && _nextPageFuture == null) {
      _controller.emitData(data.copyWith(clearNextPageError: true));
    }
    return fetchNextPage();
  }

  @override
  StatefulData<LoadMoreData<TPage, PP>> current() => _controller.currentState;

  @override
  LoadMoreData<TPage, PP>? currentData() => _controller.currentData;

  /// Drops all pages and in-flight results, resetting the feed to [DataInitial].
  ///
  /// The wrapped source is not invalidated.
  @override
  void invalidate() {
    _resetRequests();
    _filter = null;
    _controller.emitInitial();
  }

  /// Retries the first page if it failed, or the next page if that failed.
  @override
  FutureOr<void> recover() {
    final filter = _filter;
    if (filter == null) return null;
    if (_controller.isError) {
      refresh(filter).ignore();
    } else if (_controller.currentData?.hasNextPageError ?? false) {
      retryNextPage().ignore();
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _resetRequests();
    await _sourceSubscription.cancel();
    await _controller.dispose();
  }

  Future<LoadMoreData<TPage, PP>> _loadFirstPage(F filter) {
    final filterChanged = _filter != filter;
    _resetRequests();
    final generation = _generation;
    _filter = filter;

    final previous = filterChanged ? null : _controller.currentData;
    if (previous != null) {
      _controller.emitRefreshing(
        previous.copyWith(isFetchingNextPage: false, clearNextPageError: true),
      );
    } else {
      _controller.emitLoading();
    }

    return _firstPageFuture = _fetchFirstPage(filter, generation, previous);
  }

  Future<LoadMoreData<TPage, PP>> _fetchFirstPage(
    F filter,
    int generation,
    LoadMoreData<TPage, PP>? previous,
  ) async {
    try {
      final page = await source.refresh((
        filter: filter,
        page: initialPageParam,
      ));
      final pages = [page];
      final data = LoadMoreData<TPage, PP>(
        pages: pages,
        pageParams: [initialPageParam],
        nextPageParam: nextPageParam(page, pages),
      );
      if (generation == _generation) {
        _controller.emitData(data);
      }
      return data;
    } catch (error, stackTrace) {
      if (generation == _generation) {
        _controller.emitError(
          error,
          stackTrace: stackTrace,
          staleData: previous,
        );
      }
      rethrow;
    } finally {
      if (generation == _generation) {
        _firstPageFuture = null;
      }
    }
  }

  Future<void> _fetchNextPage(F filter, PP pageParam, int generation) async {
    try {
      final page = await source.refresh((filter: filter, page: pageParam));
      final latest = _controller.currentData;
      if (generation != _generation || latest == null) return;

      final pages = [...latest.pages, page];
      _controller.emitData(
        LoadMoreData<TPage, PP>(
          pages: pages,
          pageParams: [...latest.pageParams, pageParam],
          nextPageParam: nextPageParam(page, pages),
        ),
      );
    } catch (error, stackTrace) {
      final latest = _controller.currentData;
      if (generation != _generation || latest == null) return;

      _controller.emitData(
        latest.copyWith(
          isFetchingNextPage: false,
          nextPageError: error,
          nextPageStackTrace: stackTrace,
        ),
      );
    } finally {
      if (generation == _generation) {
        _nextPageFuture = null;
      }
    }
  }

  /// Invalidates all in-flight requests so their results are dropped.
  void _resetRequests() {
    _generation++;
    _firstPageFuture = null;
    _nextPageFuture = null;
    final done = _nextPageDone;
    _nextPageDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Reacts to the wrapped source being invalidated (a transition to [DataInitial]).
  void _onSourceState(StatefulData<TPage> state) {
    if (state is! DataInitial<TPage>) {
      _sourceHadState = true;
      return;
    }
    if (!_sourceHadState || _isDisposed) return;
    _sourceHadState = false;

    final filter = _filter;
    if (filter != null && _controller.hasListeners) {
      refresh(filter).ignore();
    } else {
      invalidate();
    }
  }
}
