---
name: trooper-reactive-data-flow
description: Guides implementing data sources, multi-tier caching, SWR (Stale-While-Revalidate), push streams, and mutations using the Trooper framework. Use when building repositories, remote/local queries, WebSocket streams, or managing reactive state with Trooper.
---

# Trooper Reactive Data-Flow Guide

`trooper` is an architectural blueprint and reactive data-flow framework for Dart 3.5+ applications. It provides deterministic caching, zero-flicker Stale-While-Revalidate (SWR), request coalescing, and structured lifecycle management.

## Contents
- [Core Philosophy](#core-philosophy)
- [State Model: `StatefulData<T>`](#state-model-statefuldatat)
- [Component Overview](#component-overview)
- [Working with Parameters (`P extends Parameter`)](#working-with-parameters-p-extends-parameter)
- [QueryTrooper & KeyedQueryTrooper](#querytrooper--keyedquerytrooper)
- [LocalTrooper & KeyedLocalTrooper](#localtrooper--keyedlocaltrooper)
- [StreamTrooper & KeyedStreamTrooper](#streamtrooper--keyedstreamtrooper)
- [TrooperMutation](#troopermutation)
- [TrooperController & Architecture](#troopercontroller--architecture)
- [Critical Rules & Gotchas](#critical-rules--gotchas)
- [Step-by-Step Feature Workflow](#step-by-step-feature-workflow)
- [Production-Grade Code Examples](#production-grade-code-examples)

---

## Core Philosophy

1. **Separation of Concerns**: Data access, caching, and stream lifecycles belong inside Troopers, aggregated by `TrooperController`. Never place network requests, TTL timers, or caching logic inside UI widgets.
2. **Accessors over Raw Objects**: Components consume data via `Accessor<T, P>` or `KeyedAccessor<K, T, P>`, providing a clean read-only interface (`get`, `refresh`, `trigger`, `watch`, `current`, `currentData`).
3. **Zero-Flicker SWR**: `DataRefreshing<T>` extends `DataLoaded<T>`. When fresh data is being revalidated in the background, active UIs continue to render the stale cached data without jarring layout shifts or loading spinners.
4. **Deterministic Lifecycle**: All troopers implement `LifecycleAware` (`initialize`, `pause`, `resume`, `recover`, `dispose`). Parent controllers automatically propagate lifecycle transitions to their child troopers.

---

## State Model: `StatefulData<T>`

Trooper models state using an algebraic sealed class hierarchy:

```
                  StatefulData<T> (sealed)
                 /       |       \        \
       DataInitial   DataLoading  DataLoaded  DataError
                                      |
                                DataRefreshing
```

### Inspecting State via Pattern Matching
Always use Dart 3 switch expressions or pattern matching to render or process state:

```dart
final state = trooper.current();

final statusText = switch (state) {
  DataInitial() => 'Idle',
  DataLoading(:final progress) => 'Loading (${progress != null ? (progress * 100).toInt() : 0}%)',
  DataRefreshing(:final data) => 'Refreshing: $data',
  DataLoaded(:final data) => 'Loaded: $data',
  DataError(:final error, :final staleData) =>
    staleData != null ? 'Error ($error), showing cached: $staleData' : 'Failed: $error',
};
```

### Key Boolean Getters
- `state.isInitial`: `true` if untouched.
- `state.isLoading`: `true` during both cold fetch (`DataLoading`) and SWR (`DataRefreshing`).
- `state.isLoaded`: `true` if valid data is present (`DataLoaded` or `DataRefreshing`).
- `state.isRefreshing`: `true` specifically during background revalidation (`DataRefreshing`).
- `state.isError`: `true` if in error state (`DataError`).
- `state.dataOrNull`: Returns `T?` if loaded/refreshing, or stale data if present on error.

---

## Component Overview

| Component | Purpose | Key Capabilities |
|---|---|---|
| `QueryTrooper<T, P>` | Asynchronous data fetching | L1 memory cache, L2 disk cache, SWR, request coalescing |
| `KeyedQueryTrooper<K, T, P>` | Dynamic collection of queries by key `K` | Per-key state, batch operations (`getAll`, `getMany`), subscript operator `[key]` |
| `LocalTrooper<T, P>` | In-memory mutable state | Synchronous updates (`set`, `update`, `reset`), optional L2 persistence |
| `KeyedLocalTrooper<K, T, P>` | Keyed collection of local state | Per-key state, batch operations (`setAll`, `updateAll`, `resetKeys`, `getAll`) |
| `StreamTrooper<T, P>` | Push streams (WebSockets, SSE) | Lifecycle hooks (`onConnect`, `onDisconnect`, `onRefresh`), auto-disconnect |
| `KeyedStreamTrooper<K, T, P>` | Multi-channel push streams | Keyed channels, batch connections (`connectKeys`, `disconnectKeys`) |
| `TrooperMutation<T, P>` | Write operations / Commands | Strict FIFO queue, declarative invalidation (`invalidateOnSuccess`) |
| `TrooperController` | Module aggregator | Shared cache, query queue, telemetry, automatic child lifecycle propagation |

---

## Working with Parameters (`P extends Parameter`)

In Trooper, `Parameter` is a typedef for `Record`.

### Parameterized Troopers (`P != ()`)
For queries that require arguments (e.g. `({int id})` or `({String query, int page})`):
- `get(P parameter, {bool forceRefresh = false})` requires the parameter.
- `refresh(P parameter)` requires the parameter.
- `trigger(P parameter, {bool forceRefresh = false})` requires the parameter.
- `watch({P? initialParameter, bool eager = false})`: `initialParameter` is optional. If provided and `eager: true`, an initial fetch is triggered immediately.

### Parameterless Troopers (`P == ()`)
When no arguments are required, declare `P` as `()`. Trooper provides extension methods (`ParameterlessAccessor`, `ParameterlessQueryTrooper`, etc.) allowing calls without arguments:
- `await query.get()` (no `const ()` needed!)
- `await query.refresh()`
- `query.trigger()`
- `query.watch()`

### Synchronous Inspection (`current()` and `currentData()`)
`current()` and `currentData()` are **always parameterless**:
- `final state = query.current();` -> returns `StatefulData<T>`
- `final data = query.currentData();` -> returns `T?`
- On keyed troopers, inspect specific keys via `query.currentKey(key)` and `query.currentKeyData(key)`.

---

## QueryTrooper & KeyedQueryTrooper

### Creating a QueryTrooper
```dart
final userQuery = QueryTrooper<User, ({int id})>(
  namespace: 'users',
  fetch: (param) => api.fetchUser(param.id),
  config: const TrooperConfig(
    timeToLive: Duration(minutes: 15),
    stalePolicy: StalePolicy.keepStaleWhileRevalidate,
    conflictPolicy: QueryConflictPolicy.forward,
    deduplicate: true,
  ),
);
```

### Cooperative Cancellation
For long-running or cancellable HTTP requests:
```dart
final searchTrooper = QueryTrooper<List<Item>, ({String query})>.cancellable(
  namespace: 'search',
  fetch: (param, token) async {
    final response = await httpClient.get('/search?q=${param.query}', cancelToken: token);
    token.throwIfCancelled();
    return parseItems(response);
  },
);
```

### KeyedQueryTrooper
Partition queries dynamically by entity key (e.g. user ID, product slug):
```dart
final productQuery = KeyedQueryTrooper<String, Product, ()>(
  namespace: 'products',
  fetch: (slug, _) => api.fetchProductBySlug(slug),
  config: const TrooperConfig(timeToLive: Duration(minutes: 30)),
);

// Access a single key as a standard Accessor<Product, ()>:
final laptopAccessor = productQuery['macbook-pro'];
final product = await laptopAccessor.get();

// Batch operations:
final products = await productQuery.getAll(['macbook-pro', 'ipad-air'], const ());
```

---

## LocalTrooper & KeyedLocalTrooper

Used for local state that changes immediately upon user interaction:

```dart
final counter = LocalTrooper<int, ()>(
  namespace: 'counter',
  initialValue: 0,
);

counter.update((current) => current + 1);
counter.set(10);
counter.reset();
```

### Persistent Storage Support
Provide a `TrooperCodec` and `storage` backend to persist state across app restarts:
```dart
final themeSetting = LocalTrooper<String, ()>(
  namespace: 'theme_mode',
  initialValue: 'system',
  codec: TrooperCodec.string,
  config: TrooperConfig(storage: SharedPreferencesStorageBackend()),
);
```

---

## StreamTrooper & KeyedStreamTrooper

Connects external push streams (WebSockets, SSE, Firebase listeners) to the Trooper reactive pipeline:

```dart
final liveTicker = StreamTrooper<double, ({String symbol})>(
  namespace: 'ticker',
  streamFactory: (param, token) => webSocketClient.subscribe(param.symbol),
  onConnect: (param, token) async => print('Subscribing to ${param.symbol}'),
  onDisconnect: () => print('Unsubscribed from ticker'),
  onRefresh: (param) => webSocketClient.requestSnapshot(param.symbol),
  keepAlive: false, // Disconnects when last watcher unsubscribes
);
```

---

## TrooperMutation

Use `TrooperMutation` for actions that mutate server-side state (POST, PUT, DELETE).

### Key Features:
- **FIFO Execution**: Rapid clicks are queued and processed sequentially without race conditions.
- **Automatic Invalidation**: Automatically invalidates queries when the mutation succeeds.

```dart
final updateProfile = TrooperMutation<User, ({String name, String email})>(
  namespace: 'update_profile',
  action: (param) => api.updateProfile(name: param.name, email: param.email),
  invalidateOnSuccess: [userQuery],
);

// Execute directly:
final updatedUser = await updateProfile((name: 'Alice', email: 'alice@example.com'));
```

---

## TrooperController & Architecture

Group related troopers into a feature controller. The controller automatically provides:
- Shared memory cache across all child troopers.
- Shared query and mutation queues.
- Automatic cascade of `initialize()`, `pause()`, `resume()`, `recover()`, and `dispose()`.

```dart
class UserFeatureController extends TrooperController {
  UserFeatureController({required ApiClient api}) {
    userProfile = query<UserProfile, ({int id})>(
      namespace: 'user_profile',
      fetch: (param) => api.getUser(param.id),
      config: const TrooperConfig(timeToLive: Duration(minutes: 10)),
    );

    editBio = mutation<void, ({int id, String bio})>(
      namespace: 'edit_bio',
      action: (param) => api.updateBio(param.id, param.bio),
      invalidateOnSuccess: [userProfile],
    );
  }

  late final QueryTrooper<UserProfile, ({int id})> userProfile;
  late final TrooperMutation<void, ({int id, String bio})> editBio;
}
```

---

## Critical Rules & Gotchas

1. **Parameterless `current()` & `currentData()`**:
   - `query.current()` and `query.currentData()` never take arguments.
   - Keyed troopers use `query.currentKey(key)` and `query.currentKeyData(key)` to inspect an individual key.
2. **`eager` Defaults to `false`**:
   - Calling `trooper.watch()` does not trigger an automatic network call unless `eager: true` is explicitly provided.
3. **Invalidation Scope**:
   - `trooper.invalidate()` clears all cache entries for that namespace across all parameters.
   - `keyedTrooper.invalidate()` clears all keys and parameters in that namespace.
   - `keyedTrooper.invalidateKey(key)` clears that specific key across all parameters.
4. **Named Parameters for Optionals**:
   - Always use named parameters for optional arguments (e.g. `cancel({String? reason})`, `watch({P? initialParameter, bool eager = false})`).
5. **Class Naming Consistency**:
   - Always use `QueryTrooper` (not `TrooperQuery`).
   - Always use `KeyedQueryTrooper` (not `KeyedTrooperQuery`).

---

## Step-by-Step Feature Workflow

When adding a new data feature:

- [ ] **Step 1: Define Models**. Create immutable data classes for the domain entity.
- [ ] **Step 2: Choose Trooper Type**.
  - Read-only HTTP/REST -> `QueryTrooper` (or `KeyedQueryTrooper` if partitioned by key).
  - Mutable local state -> `LocalTrooper` (or `KeyedLocalTrooper`).
  - Push stream / WebSocket -> `StreamTrooper` (or `KeyedStreamTrooper`).
  - Command / Action -> `TrooperMutation`.
- [ ] **Step 3: Configure Caching & SWR**.
  - Set `timeToLive` based on data volatility (e.g. 5 minutes).
  - Set `stalePolicy: StalePolicy.keepStaleWhileRevalidate` for smooth UX.
- [ ] **Step 4: Compose in a Controller**. Subclass `TrooperController` and register the troopers using factory methods (`query`, `keyedQuery`, `mutation`, `local`).
- [ ] **Step 5: Write Unit Tests**. Use `test()` or `fake_async` to verify initial fetch, SWR background update, and mutation invalidation.

---

## Production-Grade Code Examples

### 1. Complete Repository Module with Caching, SWR, and Mutation

```dart
import 'package:trooper/trooper.dart';

class ArticleRepository extends TrooperController {
  ArticleRepository({required ApiClient api}) {
    // Keyed query for individual articles
    articleDetails = keyedQuery<int, Article, ()>(
      namespace: 'article_details',
      fetch: (id, _) => api.getArticle(id),
      config: const TrooperConfig(
        timeToLive: Duration(minutes: 10),
        stalePolicy: StalePolicy.keepStaleWhileRevalidate,
      ),
    );

    // List query with pagination/filtering
    articleList = query<List<Article>, ({String category, int page})>(
      namespace: 'article_list',
      fetch: (p) => api.getArticles(category: p.category, page: p.page),
      config: const TrooperConfig(
        timeToLive: Duration(minutes: 5),
        deduplicate: true,
      ),
    );

    // Mutation that invalidates both the list and the affected article
    publishArticle = mutation<Article, ({String title, String category})>(
      namespace: 'publish_article',
      action: (p) => api.postArticle(title: p.title, category: p.category),
      invalidateOnSuccess: [articleList, articleDetails],
    );
  }

  late final KeyedQueryTrooper<int, Article, ()> articleDetails;
  late final QueryTrooper<List<Article>, ({String category, int page})> articleList;
  late final TrooperMutation<Article, ({String title, String category})> publishArticle;
}
```
