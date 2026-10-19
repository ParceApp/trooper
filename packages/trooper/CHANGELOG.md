## 1.0.0

First stable release. The public API is frozen and follows semantic versioning.
From 1.0.0 on, public symbols are deprecated for at least one minor release before they are
removed in the next major release; see `docs/DEPRECATION.md`.

### Breaking: API freeze for 1.0

The public API is prepared for the 1.0 freeze (decisions in `docs/audit/api-freeze-decisions.md`,
baseline in `docs/api/`). From 1.0 on, removing or changing a public symbol needs a major
release.

#### Migration from 0.1.x

| 0.1.x | 1.0 |
| :--- | :--- |
| `query.get()`, `query.refresh()`, `query.trigger()`, `mutation()`, `keyed.getKey(k)`, `local.set(v)`, … (the `Parameterless*` extensions; they were shadowed and never callable) | pass `()` explicitly: `query.get(())`, `mutation(())`, `keyed.getKey(k, ())`, `local.set(v, ())`; `watch(initialParameter: (), eager: true)` |
| `query(fetch: …)` / `query(cancellableFetch: …)` | `query(fetch: …)` / `cancellableQuery(fetch: (p, token) => …)` |
| `keyedQuery(cancellableFetch: …)` | `cancellableKeyedQuery(fetch: (k, p, token) => …)` |
| `mutation(cancellableAction: …)` | `cancellableMutation(action: (p, token) => …)` |
| `keyedLocal(initialValueFactory: …)` | `keyedLocalBuilder(initialValueFactory: …)` |
| `controller.executeOrder66()` | `controller.clearAll()` |
| `TrooperConfig.setDefaultConfig(…)`, `Trooper.setDefaultConfig(…)`, `TrooperConfig.defaultConfig` | `TrooperConfig.setDefault(…)` once in `main()` before the first trooper, read via `TrooperConfig.current`; or `TrooperController(defaultConfig: …)` |
| `config.queryConflictPolicy` | `config.conflictPolicy` |
| `ConflictPolicy` | `QueryConflictPolicy` |
| `keyedAccessor.key(k)` | `keyedAccessor[k]` |
| `trooper()` (returned the accessor) | `trooper.accessor` |
| `KeyedLocalTrooper.currentKeyState(k)` | `currentKey(k)` |
| overriding `initialize()`, `pause()`, `resume()`, `recover()`, `didChangeDependencies()`, `dispose()` in a `TrooperController` | override `onInit`, `onPause`, `onResume`, `onRecover`, `onDependenciesChanged`, `onDispose` (the drivers are `@nonVirtual`) |
| `streamController:`, `stream:`, `streamManager:` constructor parameters; `StatefulStreamController`, `KeyedStatefulStream`, `KeyedTrooperAccessor` | removed from the public API; observe state through `watch`/`stream`, `watchAll()`, `watchKeys()` |
| `class X extends QueryTrooper` / `implements QueryTrooper` (and the other concrete troopers, `TrooperConfig`, `RetryPolicy`, `CacheStore`, queues, side-effect classes, `InMemoryStorageBackend`, `StorageEnvelope`, `TelemetryHub`, `ConsoleTrooperLogger`) | these classes are `final`; mock through `Accessor`/`KeyedAccessor` and `FakeAccessor`, wrap `InMemoryStorageBackend` by delegation |
| `class X extends Trooper` / `KeyedTrooper` | not supported (`abstract base`, internal helpers) |
| `StorageBackend.delete` returning `Future<String?>`; `clear()`, `containsKey()` | `Future<void> delete(key)`; `clear` and `containsKey` removed (Trooper never called them) |
| exhaustive `switch` over `TrooperException` or `TrooperEvent` | add a default case; both are `abstract final` and can gain subtypes in minor releases |
| codec failures as raw `FormatException` etc. | `TrooperCodecException` (original error in `.error`), in `PersistenceErrorEvent` and from `LocalTrooper.set`/`setAsync` |
| `class X extends DataLoaded` | not allowed (`final`) |

#### Behavior changes

* **Uniform behavior after `dispose()`** (documented on `LifecycleAware.dispose`): loading,
  writing, emitting, connecting, executing and watching throw a `StateError` (methods
  returning a `Future` complete with it). Snapshots (`current()`, `currentData()`) return the
  last state; `invalidate()`, `pause()`, `resume()`, `recover()`, `didChangeDependencies()`
  and cleanup calls are no-ops. Before, `LocalTrooper`, `KeyedLocalTrooper` and `CacheStore`
  silently kept working, `StreamTrooper` threw `TrooperCancelledException`, a `QueryTrooper`
  on a shared queue kept fetching, and `KeyedStreamTrooper.getKey` never completed.
* `TrooperMutation.execute`, `TrooperQueryQueue.execute` and `TrooperMutationQueue.add` after
  dispose return a failed `Future` instead of throwing synchronously.
* `TrooperCodec.encode`/`decode` wrap every failure in `TrooperCodecException`.

#### Other changes

* **New (additive API)**: `TrooperConfig.setDefault(config)` sets a global default
  configuration, read through `TrooperConfig.current`. It can only be set before the first
  trooper, mutation or controller field is created; afterwards it throws a `StateError` that
  says to call it in `main()`. `TrooperConfig.resetDefault()` (`@visibleForTesting`) restores
  `const TrooperConfig()` and lifts the lock. A trooper uses, in this order: its own `config`,
  the controller's `defaultConfig`, the global default, `const TrooperConfig()`.
* **`LoadMore<TPage, F, PP>`**: Load-more (infinite scroll) decorator over an existing page query with `fetchNextPage()`, `retryNextPage()`, and `hasNextPage`, plus the `TrooperController.loadMore(...)` factory.
* **`LoadMoreData<TPage, PP>`**: Accumulated pages with next-page status; `items` flattens list pages.
* **Docs**: Pagination guide for classic pages and load more.
* **Breaking (L2 format)**: `QueryKey.storageKey` now uses the versioned layout `trooper:1:<namespace>:<parameter>[:<key>]` with URI-encoded segments. Entries written by 0.1.0-beta.1 are no longer read and stay in the backend until the app clears it.
* **Fix**: L2 keys no longer collide for parameters whose `toString()` is the default `Instance of '…'`; such keys now skip L2 storage and report a `PersistenceErrorEvent` (see `QueryKey.hasStableStorageKey`).
* **Fix**: `invalidate()`, `invalidateKey()`, `removeKey()`, `KeyedTrooper.clearAll()` and `TrooperController.clearAll()` now delete persisted L2 entries of the namespace (or key), including entries from earlier sessions. L2 reads wait for a running purge, so a `get()` right after logout never sees the previous user's data. Requires `StorageBackend.getAllKeys()` to list keys of all sessions.
* **Docs**: `invalidate()` cancels in-flight requests; their callers receive a `TrooperCancelledException`.
* **Fix**: `QueryConflictPolicy.parallel` no longer lets an older response overwrite a newer one in stream, cache, or storage.
* **Fix**: `KeyedStreamTrooper.dispose()` no longer fails with `ConcurrentModificationError` when a listener changes keys or disposes during cancellation.
* **Docs**: New README section "Persistence & Sensitive Data": L2 values and keys are plain text, how to encrypt values with a `StorageBackend` decorator, and a `flutter_secure_storage` backend example. Same note in the `StorageBackend`/`TrooperCodec` dartdoc and the skill.
* **Behavior change / new (additive API)**: `ConsoleTrooperLogger` masks query parameters and entity keys as a short stable hash by default, also inside Trooper's own error messages; `ConsoleTrooperLogger(logParameters: true)` prints them in plain text.
* **New (additive API)**: `releaseUnwatchedKeys` on `KeyedQueryTrooper`, `KeyedStreamTrooper` (also `.fromStream`) and the `TrooperController.keyedQuery`/`keyedStream` factories, default `false`. When enabled, a key's in-memory state (stream controller, last parameter, last stream data) is dropped once it has no listener, no request in flight and no open connection; L1 cache and L2 storage are kept.
* **New (additive API)**: `CacheStore(maxEntries: …)` caps the L1 store with least-recently-used eviction; the default stays unbounded. Memory bounds and defaults are documented on `CacheStore`.
* **New (additive API)**: `RetryPolicy.jitter` (also on `RetryPolicy.linear` and `.exponential`), default `RetryPolicy.defaultJitter = 0.5`. Each retry delay is drawn from `[d * (1 - jitter), d]`, so clients that failed together no longer retry in lockstep; `maxDelay` stays the upper bound. **Behavior change**: retry delays are randomized by default; pass `jitter: 0` for exact delays. `RetryPolicy.none()` and `.immediate()` use no jitter.
* **Docs**: README retry example used a non-existent `multiplier:` parameter; it is `backoffMultiplier:`.
* **Behavior change**: Errors thrown by side-effect callbacks (`onData`, `onError`, `onRequestStarted`, `onStarted`, `onSuccess`, …, sync or async), `TrooperCancelToken` listeners and `invalidate()` of controller targets are no longer swallowed. They are reported to the current `Zone` as uncaught errors; the request, its result and the remaining callbacks are unaffected.
* **Fix**: Every L2 failure is now reported as `PersistenceErrorEvent`: unreadable or undecodable entries on restore (then deleted and refetched), failed deletes, and `StreamTrooper`/`KeyedStreamTrooper` write and encode failures, which were silently dropped before.
* **Fix**: L2 entries without an envelope `version` or with a version other than `StorageEnvelope.currentVersion` (e.g. written by a newer app release) are discarded and fetched again instead of being decoded as the current format. The envelope format v1 is documented as stable.
* **Fix**: `QueryConflictPolicy.forward` now always resolves a superseded caller with the newer request's result (or error), as documented. Before, the caller received the superseded result if that fetch ignored its token and answered first, which also reached stream and cache briefly, and it failed with `TrooperCancelledException` if the fetch honored its token or was waiting for a retry.
* **Fix**: A `LoadMore.fetchNextPage()` that a filter change, refresh or invalidate overtakes now completes right away, independent of the source's conflict policy.
* **Fix**: A cancelled `TrooperMutation` whose action ignores its `TrooperCancelToken` no longer emits `DataLoaded`, runs `invalidateOnSuccess` or calls `onSuccess`; it fails with `TrooperCancelledException` like a cooperative cancel.

## 0.1.0-beta.1

Initial public release of Trooper, an architectural blueprint and reactive data-flow framework for Dart applications.

### Core Reactive Engine
* **`QueryTrooper<T, P>`**: Asynchronous data queries with multi-tier caching, Stale-While-Revalidate background updates, and automatic request deduplication.
* **`KeyedQueryTrooper<K, T, P>`**: Dynamic collection of queries partitioned by entity key `K` (e.g. ID, slug) with batch reading support (`getAll`, `getMany`).
* **`LocalTrooper<T, P>`**: In-memory reactive state management with optional persistent L2 storage synchronization.
* **`KeyedLocalTrooper<K, T, P>`**: In-memory state collections partitioned dynamically by key with batch operations (`setAll`, `updateAll`, `resetKeys`, `getAll`).
* **`StreamTrooper<T, P>`**: Push stream bridge for WebSockets, Server-Sent Events, and broadcast channels with connection lifecycle control.
* **`KeyedStreamTrooper<K, T, P>`**: Multi-channel push streams partitioned dynamically by key with batch connection support (`connectKeys`, `disconnectKeys`, `getAll`).
* **`TrooperMutation<T, P>`**: Command operations with sequential execution queuing and declarative cache invalidation (`invalidateOnSuccess`).

### Architecture & Controller
* **`TrooperController`**: Central composition unit for grouping related queries, mutations, and local state into cohesive feature modules.
* **Hierarchical Lifecycle**: Deterministic propagation of `initialize`, `pause`, `resume`, `recover`, and `dispose` across all managed child components.
* **Resource Sharing**: Automatic sharing of cache stores, query queues, and telemetry hubs across controller children to prevent memory leaks and redundant resources.

### State Model & SWR
* **`StatefulData<T>`**: Sealed algebraic data hierarchy for Dart 3 pattern matching (`DataInitial`, `DataLoading`, `DataLoaded`, `DataRefreshing`, `DataError`).
* **Zero-Flicker SWR**: `DataRefreshing<T>` inherits from `DataLoaded<T>`, ensuring active UI components continue displaying valid data during background revalidation without layout shift.

### Concurrency & Resilience
* **`TrooperQueryQueue`**: Coalesces concurrent identical read requests into a single in-flight `Future`, managing conflict policies (`forward`, `cancel`, `parallel`).
* **`TrooperMutationQueue`**: Sequential FIFO execution queue preventing race conditions during rapid state updates.
* **`TrooperCancelToken`**: Cooperative cancellation token support with listener registration and teardown isolation.

### Caching & Storage
* **`CacheStore`**: In-memory L1 cache with configurable time-to-live (TTL), proactive sweep eviction, and cache namespace invalidation.
* **`StorageBackend` & `TrooperCodec`**: Extensible interface for asynchronous L2 disk/persistent caching (e.g. SQLite, Hive, SharedPreferences).

### Telemetry & Diagnostics
* **`TelemetryHub`**: Diagnostic event pipeline emitting structured `TrooperEvent` objects for cache hits, cache misses, request durations, and failures.
* **`TrooperLogger`**: Console and pluggable logging implementations for debugging and performance auditing.
