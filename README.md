# Trooper Monorepo

[![pub package: trooper](https://img.shields.io/pub/v/trooper.svg)](https://pub.dev/packages/trooper)
[![pub package: trooper_bloc](https://img.shields.io/pub/v/trooper_bloc.svg)](https://pub.dev/packages/trooper_bloc)
[![Dart SDK](https://img.shields.io/badge/Dart-3.5%2B-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.24-02569B.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

An architectural blueprint and high-performance reactive data-flow framework for Dart and Flutter. Trooper delivers deterministic multi-tier caching, zero-flicker Stale-While-Revalidate (SWR) background updates, request coalescing, push streams, commands, snapshot-locking, and first-class BLoC/Cubit state derivation.

```text
       ┌─────────────────────────────────────────────────────────────┐
       │                       INBOUND PORTS                         │
       │   Flutter UI (BlocBuilder, TlocEffectListener) │ CLI/Tests  │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │                    PRESENTATION LAYER                       │
       │                 trooper_bloc (Tloc / Tubit)                 │
       │     (Reactive derivation, snapshot-locking, effects)        │
       └──────────────────────────────┬──────────────────────────────┘
                                      │ (Watches Accessors)
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │                    APPLICATION LAYER                        │
       │                     TrooperController                       │
       │    (Feature scoping, shared caches, lifecycle management)   │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │                       TROOPER ENGINE                        │
       │   • QueryTrooper (SWR Caching)   • KeyedQueryTrooper        │
       │   • LocalTrooper (Memory State)  • KeyedLocalTrooper        │
       │   • StreamTrooper (Push/Sockets) • KeyedStreamTrooper       │
       │   • TrooperMutation (Commands)   • TrooperQueryQueue        │
       │   • StatefulData (State Model)   • CacheStore (L1 / L2)     │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │                      OUTBOUND ADAPTERS                      │
       │     REST API   │   GraphQL   │   WebSockets   │   Disk L2   │
       └─────────────────────────────────────────────────────────────┘
```

---

## Workspace Packages

This repository is organized as a unified Dart 3.5+ workspace:

| Directory | Package | Description | Pub Status |
|---|---|---|---|
| [`packages/trooper`](file:///Users/hannes/Developer/trooper/packages/trooper) | [`trooper`](https://pub.dev/packages/trooper) | Core pure Dart engine: multi-tier caching (L1/L2), zero-flicker SWR, request coalescing, push streams, mutations, and controllers | [![pub package](https://img.shields.io/pub/v/trooper.svg)](https://pub.dev/packages/trooper) |
| [`packages/trooper_bloc`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc) | [`trooper_bloc`](https://pub.dev/packages/trooper_bloc) | High-performance Flutter BLoC and Cubit integration (`Tloc`, `Tubit`), snapshot-locking, microtask batching, and presentation effects. Re-exports 100% of `trooper` | [![pub package](https://img.shields.io/pub/v/trooper_bloc.svg)](https://pub.dev/packages/trooper_bloc) |

---

## AI Agent Skills (labs.dart.dev Standard)

Both packages bundle official AI Agent Skills compatible with the Dart Agent Skills ecosystem (`labs.dart.dev`):

- **Core Data-Flow**: [`packages/trooper/skills/trooper-reactive-data-flow/SKILL.md`](file:///Users/hannes/Developer/trooper/packages/trooper/skills/trooper-reactive-data-flow/SKILL.md)
  Guidance on queries, SWR, caches, push streams, mutations, parameters, and controllers.
- **BLoC State Management**: [`packages/trooper_bloc/skills/trooper-bloc-state-management/SKILL.md`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/skills/trooper-bloc-state-management/SKILL.md)
  Guidance on `Tloc`, `Tubit`, `watch()`, `matchSources()`, snapshot-locking, presentation `Effects`, and unit testing with `FakeAccessor`.

---

## Core Framework Highlights

- **Predictable Single-Slot State Container**: Every Trooper manages a single logical state slot (or one slot per entity key `K`), avoiding multi-dimensional cache explosions.
- **Zero-Flicker SWR Guarantee**: `DataRefreshing<T>` extends `DataLoaded<T>`, ensuring existing cached data remains visible to UI widgets during background fetches without layout jumps.
- **Request Coalescing & Stampede Protection**: 50 concurrent requests for the same query slot share a single network invocation via `TrooperQueryQueue`.
- **Snapshot-Locking in BLoC**: In `trooper_bloc`, source states are frozen at the start of derivation cycles, preventing state tearing during asynchronous operations.
- **Microtask Batching**: Multiple simultaneous source updates within the same event loop coalesce into a single UI transition.
- **One-Off Presentation Effects**: `Effects<F>` mixin and `TlocEffectListener` handle snackbars, dialogs, and navigation cleanly without state pollution.
- **Conflict Policies**: Declarative conflict handling via `QueryConflictPolicy.forward`, `QueryConflictPolicy.cancel`, or `QueryConflictPolicy.parallel`.
- **Resilience**: Configurable exponential/linear `RetryPolicy` and granular request timeouts with `TrooperConfig(timeout: ...)`.
- **Batch Operations**: First-class bulk operations across all keyed variants (`getAll`, `setAll`, `updateAll`, `resetKeys`, `connectKeys`, `disconnectKeys`).
- **Telemetry & DevTools**: Structured, zero-allocation diagnostic events dispatched via `TelemetryHub`.
- **Multi-Tier Persistence**: In-memory L1 cache (`CacheStore`) paired with pluggable L2 disk storage (`StorageBackend`) and `StorageEnvelope`.

---

## Quickstart

### Option A: Pure Dart / Backend / CLI (`trooper`)

#### 1. Add Dependency
```yaml
dependencies:
  trooper: ^0.1.0-beta.1
```

#### 2. Define a Feature Controller
```dart
import 'package:trooper/trooper.dart';

class ArticleController extends TrooperController {
  ArticleController(this._api) : super('ArticleController');

  final ApiService _api;

  // Single cached query with SWR and exponential retries
  late final feed = query<List<Article>, ()>(
    namespace: 'articles_feed',
    fetch: (_) => _api.getLatestArticles(),
    config: const TrooperConfig(
      timeToLive: Duration(minutes: 5),
      retryPolicy: RetryPolicy.exponential(maxRetries: 3),
      timeout: Duration(seconds: 10),
    ),
  );

  // Keyed query for individual articles partitioned by ID
  late final article = keyedQuery<int, Article, ()>(
    namespace: 'article_detail',
    fetch: (id, _) => _api.getArticle(id),
    config: const TrooperConfig(timeToLive: Duration(hours: 1)),
  );

  // Command mutation that invalidates the feed upon success
  late final publish = mutation<Article, ({String title, String body})>(
    namespace: 'publish_article',
    action: (param) => _api.createArticle(param.title, param.body),
    invalidateOnSuccess: [this],
  );
}
```

#### 3. Consume in Application
```dart
// Fetch cached or fresh data
final articles = await controller.feed.get();

// React to state changes via pattern matching
controller.feed.watch().listen((state) {
  switch (state) {
    case DataInitial():
      print('Idle');
    case DataLoading():
      print('Initial loading...');
    case DataRefreshing(:final data):
      print('Revalidating in background, showing ${data.length} articles');
    case DataLoaded(:final data):
      print('Loaded: ${data.length} articles');
    case DataError(:final error):
      print('Error: $error');
  }
});
```

---

### Option B: Flutter + BLoC (`trooper_bloc`)

When using Flutter, depend on `trooper_bloc`. It re-exports 100% of `package:trooper/trooper.dart`:

#### 1. Add Dependency
```yaml
dependencies:
  trooper_bloc: ^0.1.0-beta.1
```

#### 2. Implement `Tloc`
```dart
import 'dart:async';
import 'package:trooper_bloc/trooper_bloc.dart';

sealed class FeedEvent extends TlocEvent {
  const FeedEvent();
}

final class RefreshFeedRequested extends FeedEvent {
  const RefreshFeedRequested();
}

sealed class FeedState {
  const FeedState();
}

final class FeedLoadingState extends FeedState {
  const FeedLoadingState();
}

final class FeedLoadedState extends FeedState {
  const FeedLoadedState({required this.articles, required this.isRefreshing});
  final List<Article> articles;
  final bool isRefreshing;
}

final class FeedErrorState extends FeedState {
  const FeedErrorState(this.error);
  final Object error;
}

class FeedTloc extends Tloc<FeedEvent, FeedState> {
  FeedTloc(this._controller) : super(const FeedLoadingState());

  final ArticleController _controller;
  late final Watched<List<Article>> _feed;

  @override
  List<Watched<Object?>> get sources => [
    _feed = watch(_controller.feed, eager: true),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<FeedState> emit) {
    switch (_feed.state) {
      case DataLoaded(:final data, :final isRefreshing):
        emit(FeedLoadedState(articles: data, isRefreshing: isRefreshing));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<FeedState> emit) => emit(const FeedLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<FeedState> emit) =>
      emit(FeedErrorState(error));

  @override
  void handlers() {
    on<RefreshFeedRequested>((event, emit) async {
      await _controller.feed.refresh();
    });
  }
}
```

#### 3. Render in Flutter UI
```dart
class FeedView extends StatelessWidget {
  const FeedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Articles')),
      body: BlocBuilder<FeedTloc, FeedState>(
        builder: (context, state) => switch (state) {
          FeedLoadingState() => const Center(child: CircularProgressIndicator()),
          FeedErrorState(:final error) => Center(child: Text('Error: $error')),
          FeedLoadedState(:final articles, :final isRefreshing) => RefreshIndicator(
            onRefresh: () async {
              context.read<FeedTloc>().add(const RefreshFeedRequested());
            },
            child: ListView.builder(
              itemCount: articles.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(articles[index].title),
                subtitle: isRefreshing && index == 0 ? const Text('Refreshing...') : null,
              ),
            ),
          ),
        },
      ),
    );
  }
}
```

---

## Architecture at a Glance (visualized by AI 🙃)
<p align="center">
  <img src="doc/trooper_architecture_flow.gif" alt="Trooper Architecture Flow" width="880"/>
</p>

---

## Developer Workflow

This workspace supports standard Dart and Flutter commands from the repository root:

```bash
# 1. Resolve dependencies across all workspace packages
flutter pub get

# 2. Run static analysis (0 errors, 0 warnings, 0 lints)
dart analyze

# 3. Format code
dart format .

# 4. Run pure Dart test suite (trooper)
dart test packages/trooper

# 5. Run Flutter BLoC test suite (trooper_bloc)
flutter test packages/trooper_bloc

# 6. Run benchmarks
dart run packages/trooper/benchmark/trooper_benchmark.dart
```

---

## Documentation Links

- **Core Package**: [`packages/trooper/README.md`](file:///Users/hannes/Developer/trooper/packages/trooper/README.md)
- **BLoC Integration**: [`packages/trooper_bloc/README.md`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/README.md)
- **Agent Skill: Core Data-Flow**: [`packages/trooper/skills/trooper-reactive-data-flow/SKILL.md`](file:///Users/hannes/Developer/trooper/packages/trooper/skills/trooper-reactive-data-flow/SKILL.md)
- **Agent Skill: BLoC Management**: [`packages/trooper_bloc/skills/trooper-bloc-state-management/SKILL.md`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/skills/trooper-bloc-state-management/SKILL.md)
- **Changelogs**:
  - [`packages/trooper/CHANGELOG.md`](file:///Users/hannes/Developer/trooper/packages/trooper/CHANGELOG.md)
  - [`packages/trooper_bloc/CHANGELOG.md`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/CHANGELOG.md)

---

## Contributing

We welcome contributions, bug reports, and pull requests!

1. Fork the repository and create your feature branch.
2. Ensure `dart analyze` passes with 0 issues.
3. Ensure all tests pass (`dart test packages/trooper` and `flutter test packages/trooper_bloc`).
4. Submit a Pull Request.

---

## License

This project is licensed under the MIT License: see the [`LICENSE`](file:///Users/hannes/Developer/trooper/LICENSE) file for details.
