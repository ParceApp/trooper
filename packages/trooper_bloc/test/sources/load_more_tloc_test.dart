import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

typedef FeedPage = ({List<int> items, bool hasMore});

sealed class FeedEvent extends TlocEvent {
  const FeedEvent();
}

final class FeedLoadMoreEvent extends FeedEvent {
  const FeedLoadMoreEvent();
}

sealed class FeedState {
  const FeedState();
}

final class FeedLoadingState extends FeedState {
  const FeedLoadingState();
}

final class FeedLoadedState extends FeedState {
  const FeedLoadedState(this.items, {required this.hasMore});
  final List<int> items;
  final bool hasMore;
}

class FeedTloc extends Tloc<FeedEvent, FeedState> {
  FeedTloc(this.feed) : super(const FeedLoadingState());

  final LoadMore<FeedPage, (), int> feed;
  late final Watched<LoadMoreData<FeedPage, int>> pages;

  @override
  List<Watched<Object?>> get sources => [pages = watch(feed, eager: true)];

  @override
  FutureOr<MatchResult> matchSources(Emit<FeedState> emit) {
    switch (pages.state) {
      case DataLoaded(:final data):
        emit(
          FeedLoadedState([
            for (final page in data.pages) ...page.items,
          ], hasMore: data.hasNextPage),
        );
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<FeedState> emit) => emit(const FeedLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<FeedState> emit) {}

  @override
  void handlers() {
    on<FeedLoadMoreEvent>((_, _) => feed.fetchNextPage());
  }
}

void main() {
  test('Tloc drives a LoadMore feed through load more', () async {
    final source = QueryTrooper<FeedPage, ({() filter, int page})>(
      namespace: 'feed',
      fetch: (p) async => (items: [p.page], hasMore: p.page < 2),
      config: const TrooperConfig.noCache(),
    );
    final feed = LoadMore(
      source: source,
      initialPageParam: 1,
      nextPageParam: (last, all) => last.hasMore ? all.length + 1 : null,
    );
    final tloc = FeedTloc(feed);

    await pumpEventQueue();
    var state = tloc.state as FeedLoadedState;
    expect(state.items, [1]);
    expect(state.hasMore, isTrue);

    tloc.add(const FeedLoadMoreEvent());
    await pumpEventQueue();
    state = tloc.state as FeedLoadedState;
    expect(state.items, [1, 2]);
    expect(state.hasMore, isFalse);

    await tloc.close();
    await feed.dispose();
    await source.dispose();
  });
}
