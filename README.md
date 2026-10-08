# Trooper Monorepo

[![pub package](https://img.shields.io/pub/v/trooper.svg)](https://pub.dev/packages/trooper)
[![Dart SDK](https://img.shields.io/badge/Dart-3.5%2B-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![code coverage](https://img.shields.io/badge/coverage-83.8%25-brightgreen.svg)](https://github.com/ParceApp/trooper)

An architectural blueprint and high-performance reactive data-flow framework for Dart, providing multi-tier caching, Stale-While-Revalidate (SWR) background updates, request deduplication, push streams, and deterministic state management.

```text
       ┌─────────────────────────────────────────────────────────────┐
       │                       INBOUND PORTS                         │
       │       Flutter Widgets   │   BLoC / Cubits   │   CLI / Tests │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
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
       │   • TrooperQuery (SWR Caching)   • KeyedTrooperQuery        │
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

## Workspace Structure

This repository is organized as a unified Dart 3.5+ workspace:

| Directory | Package | Description | Pub Status |
|---|---|---|---|
| [`packages/trooper`](file:///Users/hannes/Developer/trooper/packages/trooper) | [`trooper`](https://pub.dev/packages/trooper) | Core pure Dart engine: caching, SWR, deduplication, streams, mutations, controller | [![pub package](https://img.shields.io/pub/v/trooper.svg)](https://pub.dev/packages/trooper) |
| `packages/trooper_flutter` | `trooper_flutter` | *(Planned)* Flutter integration widgets, builders, and lifecycle hooks | In Design |
| `packages/trooper_bloc` | `trooper_bloc` | *(Planned)* BLoC and Cubit adapters for Trooper accessors | In Design |

---

## Core Framework Highlights

- **Predictable Single-Slot State Container**: Every Trooper manages a single logical state slot (or one slot per entity key `K`), avoiding multi-dimensional cache explosion.
- **Zero-Flicker SWR Guarantee**: `DataRefreshing<T>` extends `DataLoaded<T>`, ensuring existing data remains accessible to UI widgets during background fetches without layout jumps.
- **Request Coalescing & Stampede Protection**: 50 concurrent requests for the same query slot share a single network invocation via `TrooperQueryQueue`.
- **Conflict Policies**: Declarative conflict handling via `QueryConflictPolicy.forward`, `QueryConflictPolicy.cancel`, or `QueryConflictPolicy.parallel`.
- **Resilience**: Configurable exponential/linear `RetryPolicy` and granular request timeouts with `TrooperConfig(timeout: ...)`.
- **Batch Operations**: First-class bulk operations across all keyed variants (`getAll`, `setAll`, `updateAll`, `resetKeys`, `connectKeys`, `disconnectKeys`).
- **Telemetry & DevTools**: Structured, zero-allocation diagnostic events dispatched via `TelemetryHub`.
- **Multi-Tier Persistence**: In-memory L1 cache (`CacheStore`) paired with pluggable L2 disk storage (`StorageBackend`) and `StorageEnvelope`.

---

## Quickstart

### 1. Add Dependency

Add `trooper` to your application's `pubspec.yaml`:

```yaml
dependencies:
  trooper: ^0.1.0
```

### 2. Define a Feature Controller

```dart
import 'package:trooper/trooper.dart';

class ArticleController extends TrooperController {
  ArticleController(this._api);

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

  // Command mutation that automatically invalidates the feed upon success
  late final publish = mutation<Article, ({String title, String body})>(
    namespace: 'publish_article',
    action: (param) => _api.createArticle(param.title, param.body),
    invalidateOnSuccess: [this],
  );
}
```

### 3. Consume in Presentation

```dart
// Read cached or fresh value
final articles = await controller.feed.get();

// React to state changes via pattern matching
controller.feed.watch().listen((state) {
  switch (state) {
    case DataInitial():
      print('Idle');
    case DataLoading():
      print('Initial loading...');
    case DataRefreshing(:final data):
      print('Updating in background, showing: ${data.length} items');
    case DataLoaded(:final data):
      print('Loaded: ${data.length} items');
    case DataError(:final error):
      print('Error: $error');
  }
});

// Execute mutation
await controller.publish((title: 'Hello Trooper', body: 'Modern State Flow'));
```

---

## Developer Workflow

This workspace supports standard Dart commands from the repository root:

```bash
# 1. Resolve dependencies across all workspace packages
dart pub get

# 2. Run static analysis (0 errors, 0 warnings, 0 lints)
dart analyze

# 3. Format code
dart format .

# 4. Run the entire test suite
dart test

# 5. Run tests with coverage
flutter test --coverage

# 6. Run benchmarks
dart run packages/trooper/benchmark/trooper_benchmark.dart
```

---

## Documentation Links

- **Core Package Guide**: [`packages/trooper/README.md`](file:///Users/hannes/Developer/trooper/packages/trooper/README.md)
- **Core Changelog**: [`packages/trooper/CHANGELOG.md`](file:///Users/hannes/Developer/trooper/packages/trooper/CHANGELOG.md)
- **Workspace Tasks & Specifications**:
  - [`docs/task_documentation_audit_and_cleanup.md`](file:///Users/hannes/Developer/trooper/docs/task_documentation_audit_and_cleanup.md)
  - [`docs/task_enterprise_testing_and_benchmarks.md`](file:///Users/hannes/Developer/trooper/docs/task_enterprise_testing_and_benchmarks.md)
  - [`docs/task_workspace_root_metadata.md`](file:///Users/hannes/Developer/trooper/docs/task_workspace_root_metadata.md)

---

## Contributing

We welcome contributions, bug reports, and pull requests!

1. Fork the repository and create your feature branch.
2. Ensure `dart analyze` passes with 0 issues.
3. Ensure all tests pass with `dart test` and maintain >= 80% coverage.
4. Submit a Pull Request.

---

## License

This project is licensed under the MIT License: see the [`LICENSE`](file:///Users/hannes/Developer/trooper/LICENSE) file for details.
