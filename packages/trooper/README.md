# Trooper

[![pub package](https://img.shields.io/pub/v/trooper.svg)](https://pub.dev/packages/trooper)
[![Dart SDK](https://img.shields.io/badge/Dart-3.5%2B-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

Trooper is an architectural blueprint and reactive data-flow framework for Dart, designed specifically for medium to large-scale applications.

It gives your team a clear, predictable guide for handling asynchronous data fetching, multi-tier caching, real-time push streams, retry policies, timeouts, and background revalidation. Because the core has zero Flutter dependencies, you can use the exact same data patterns across Flutter apps, backend services (Dart Frog, Serverpod), or CLI workers.

If you know TanStack Query from the web, Trooper follows a similar mental model: server data should be cached, deduplicated, and kept fresh automatically, so you can stop manually coordinating loading spinners and cache maps.

## Table of Contents

- [Why Trooper?](#why-trooper)
- [Architecture at a Glance](#architecture-at-a-glance)
- [Quickstart](#quickstart)
- [The 7 Core Building Blocks](#the-7-core-building-blocks)
- [Batch Operations for Keyed Troopers](#batch-operations-for-keyed-troopers)
- [The State Model: StatefulData](#the-state-model-statefuldata)
- [Concurrency & Request Deduplication](#concurrency--request-deduplication)
- [Retry Policies & Timeouts](#retry-policies--timeouts)
- [Cache Configuration](#cache-configuration-trooperconfig)
- [Observability & Logging](#observability--logging)
- [Testing](#testing)
- [Ecosystem](#ecosystem)
- [License](#license)

## Why Trooper?

In growing codebases, data handling often fragments when every feature invents its own way of caching, reloading, and tracking state. Trooper introduces a clean, unified architectural standard:

- **Zero-Flicker SWR (Stale-While-Revalidate)**: `DataRefreshing<T>` extends `DataLoaded<T>`. When data refreshes in the background, your UI keeps showing the existing content. No layout jumps, no unnecessary loading spinners.
- **Automatic Request Deduplication**: When multiple components request the same resource concurrently, Trooper executes only one fetch and shares the in-flight Future with all callers.
- **Declarative Retries & Timeouts**: Configure automatic exponential backoff with `RetryPolicy` and granular request timeouts with `TrooperConfig(timeout: ...)`.
- **Composition Over Inheritance**: Instead of writing dozens of boilerplate classes for every endpoint, you assemble queries, mutations, streams, and local state directly inside a feature controller (`TrooperController`).
- **Type-Safe Records**: Query keys and parameters use native Dart 3 records like `({int id})` or `(String query, int page)`. Everything is strictly typed without generating extra model classes.
- **Reliable Lifecycles**: Controllers take care of their children. When a controller is disposed, all active stream subscriptions, cache watchers, and cancellation tokens are cleaned up automatically.

## Architecture at a Glance

Trooper separates concerns into three clear layers:

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
└─────────────────────────────────────────────────────────────┘
```

## Quickstart

Add `trooper` to your `pubspec.yaml`!

### 1. Define a Feature Controller

Create a controller that groups your queries, local state, and mutations:

```dart
import 'package:trooper/trooper.dart';

class UserController extends TrooperController {
  UserController(this._api);

  final ApiService _api;

  // Single cached query with 5-minute TTL, SWR, and exponential retry
  late final userProfile = query<User, ({int id})>(
    namespace: 'user_profile',
    fetch: (param) => _api.getUser(param.id),
    config: const TrooperConfig(
      timeToLive: Duration(minutes: 5),
      retryPolicy: RetryPolicy.exponential(maxRetries: 3),
      timeout: Duration(seconds: 10),
    ),
  );

  // Keyed query for dynamic lookups partitioned by user ID
  late final orders = keyedQuery<int, List<Order>, ()>(
    namespace: 'user_orders',
    fetch: (userId, _) => _api.getOrders(userId),
    config: const TrooperConfig(timeToLive: Duration(hours: 1)),
  );

  // In-memory reactive state (e.g. active UI tab)
  late final activeTab = local<String, ()>(
    namespace: 'active_tab',
    initialValue: 'overview',
  );

  // Mutation that executes command and automatically invalidates user cache
  late final updateBio = mutation<User, ({int id, String newBio})>(
    namespace: 'update_bio',
    action: (param) => _api.updateBio(param.id, param.newBio),
    invalidateOnSuccess: [userProfile],
  );
}
```

### 2. Use the Controller

```dart
void main() async {
  final controller = UserController(api);
  await controller.initialize();

  // 1. First get fetches from network and caches result in L1 memory
  final user = await controller.userProfile.get((id: 42));
  print('Loaded: ${user.name}');

  // 2. Second get returns instantly from L1 memory cache (0ms)
  final cached = await controller.userProfile.get((id: 42));

  // 3. Query keyed data by ID via subscript operator
  final orders = await controller.orders[42].get(const ());

  // 4. Update state via mutation
  await controller.updateBio((id: 42, newBio: 'Dart enthusiast'));
  // 'userProfile' cache for user 42 was invalidated automatically!

  // 5. Clean up all resources when finished
  await controller.dispose();
}
```

## The 7 Core Building Blocks

Trooper provides seven specialized building blocks depending on what kind of data you handle:

| Building Block | Controller Method | What it is for |
| :--- | :--- | :--- |
| **`TrooperQuery<T, P>`** | `query(...)` | Asynchronous reads with caching, SWR background refresh, and request deduplication. |
| **`KeyedTrooperQuery<K, T, P>`** | `keyedQuery(...)` | Queries partitioned dynamically by entity key `K` (e.g. ID, slug, category). |
| **`LocalTrooper<T, P>`** | `local(...)` | In-memory reactive state with optional persistent storage backing. |
| **`KeyedLocalTrooper<K, T, P>`** | `keyedLocal(...)` | In-memory state partitioned by key (e.g. drafts or dynamic filters per item). |
| **`StreamTrooper<T, P>`** | `stream(...)` | Connects push-based streams (WebSockets, SSE, event buses) into `StatefulData`. |
| **`KeyedStreamTrooper<K, T, P>`** | `keyedStream(...)` | Multi-channel push streams partitioned by key (e.g. chat rooms, live sensors). |
| **`TrooperMutation<T, P>`** | `mutation(...)` | Command operations with sequential execution queuing and declarative cache invalidation. |

## Batch Operations for Keyed Troopers

All keyed troopers (`KeyedTrooperQuery`, `KeyedLocalTrooper`, `KeyedStreamTrooper`, and `KeyedAccessor`) support first-class batch operations:

```dart
// Read multiple items concurrently
final batch = await controller.orders.getAll([101, 102, 103], const ());

// Refresh multiple items concurrently bypassing cache
final refreshed = await controller.orders.refreshKeys([101, 102], const ());

// Invalidate multiple items at once
controller.orders.invalidateKeys([101, 102]);

// Batch mutate and persist local state
await drafts.setAllAsync({'doc1': 'Draft 1', 'doc2': 'Draft 2'}, const ());
```

## The State Model: StatefulData

Every query, local state, and stream emits `StatefulData<T>`, a sealed hierarchy designed for Dart 3 pattern matching:

```dart
switch (state) {
  case DataInitial():
    // Operation has not started yet
    showEmptyPlaceholder();

  case DataLoading():
    // Initial fetch in flight (no data available yet)
    showLoadingSpinner();

  case DataRefreshing(:final data):
    // SWR background refresh in flight:
    // Keep showing data, but display a subtle spinner or progress bar
    renderContent(data, isRefreshing: true);

  case DataLoaded(:final data):
    // Data is fresh and ready
    renderContent(data, isRefreshing: false);

  case DataError(:final error, :final staleData):
    // Operation failed. If staleData is present, you can show an error banner
    // while still letting the user see previously cached data!
    showError(error, fallbackData: staleData);
}
```

### Why `DataRefreshing extends DataLoaded` Matters

In standard state architectures, refreshing data often forces a jump back to a generic `Loading` state. The UI unmounts its content and shows a full-page spinner.

In Trooper, `DataRefreshing<T>` inherits from `DataLoaded<T>`. If your UI checks `state.isLoaded` or patterns on `case DataLoaded(:final data)`, it continues matching during background revalidation. Zero flicker, zero layout shifts.

## Concurrency & Request Deduplication

Trooper handles common concurrency hazards out of the box:

### Request Deduplication
If 10 components call `userProfile.get((id: 42))` at the exact same moment, `TrooperQueryQueue` coalesces them into a single in-flight `Future`. All 10 callers receive the same result without hammering your backend.

### Cooperative Cancellation
Queries and mutations support `TrooperCancelToken`. If the user leaves a screen or initiates a new query, cancel the token:

```dart
final token = TrooperCancelToken();

// Cancel if user navigates away
token.cancel('User navigated away');
```

### Sequential Mutation Queuing
When users click an "Add to Cart" or "Save" button rapidly, mutations are placed in a FIFO `TrooperMutationQueue`. Each mutation awaits the completion of the previous one, preventing race conditions on shared backend state.

## Retry Policies & Timeouts

Configure declarative retry strategies with linear or exponential backoff:

```dart
// Exponential backoff: 3 retries, initial delay 250ms, multiplier 2.0
final retryPolicy = RetryPolicy.exponential(
  maxRetries: 3,
  initialDelay: const Duration(milliseconds: 250),
  multiplier: 2.0,
  maxDelay: const Duration(seconds: 5),
  retryWhen: (error) => error is SocketException,
);

// Apply via TrooperConfig
final config = TrooperConfig(
  timeout: const Duration(seconds: 8),
  retryPolicy: retryPolicy,
);
```

## Cache Configuration (`TrooperConfig`)

Control caching behavior declaratively:

```dart
// Standard 1-minute cache with SWR
const config = TrooperConfig();

// Custom TTL with keep-stale-while-revalidate policy
const customConfig = TrooperConfig(
  timeToLive: Duration(minutes: 10),
  stalePolicy: StalePolicy.keepStaleWhileRevalidate,
);

// Ephemeral (TTL = 0, always fetches fresh data)
const noCache = TrooperConfig.noCache();
```

## Observability & Logging

Trooper includes a built-in event bus for logging and diagnostics:

```dart
// Register console logger
TelemetryHub.global.registerLogger(ConsoleTrooperLogger());

// Or listen directly to events
TelemetryHub.global.addListener((event) {
  print('[Trooper Event] $event');
});
```

Events track cache hits, cache misses, request durations, SWR triggers, persistence errors, and network failures with microsecond precision.

## Testing

Because Trooper has zero UI dependencies, testing controllers is straightforward:

```dart
test('fetches user and serves subsequent read from cache', () async {
  final api = MockApiService();
  final controller = UserController(api);
  await controller.initialize();

  // First read hits API
  final user1 = await controller.userProfile.get((id: 42));
  expect(user1.name, 'Alice');
  expect(api.fetchCount, 1);

  // Second read hits L1 cache instantly
  final user2 = await controller.userProfile.get((id: 42));
  expect(user2.name, 'Alice');
  expect(api.fetchCount, 1); // No second network call!

  await controller.dispose();
});
```

## Ecosystem

- **`trooper`**: Core data-flow, caching, and state management engine (Pure Dart).
- **`trooper_flutter`**: Flutter widgets (`TrooperBuilder`, `TrooperScope`) and lifecycle bindings.
- **`trooper_bloc`**: First-class adapters for BLoC and Cubit.

## License

MIT (c) [ParceApp](https://parceapp.de)
