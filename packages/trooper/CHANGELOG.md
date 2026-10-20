# Changelog

All notable changes to this package are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this package follows
[Semantic Versioning](https://semver.org/).

## 1.0.0

First release of Trooper, a reactive data-flow and caching framework for Dart.
The public API is stable and follows semantic versioning: public symbols are deprecated for at
least one minor release before they are removed in the next major release
(see "Versioning & Deprecation" in the repository README).

### Building blocks

* **`QueryTrooper<T, P>`**: asynchronous reads with L1/L2 caching, stale-while-revalidate
  refresh and request deduplication.
* **`KeyedQueryTrooper<K, T, P>`**: queries partitioned by an entity key `K` (ID, slug, …),
  with batch reads (`getAll`, `getMany`) and per-key invalidation.
* **`LocalTrooper<T, P>`** and **`KeyedLocalTrooper<K, T, P>`**: reactive in-memory state with
  optional persistence and batch operations (`setAll`, `updateAll`, `resetKeys`).
* **`StreamTrooper<T, P>`** and **`KeyedStreamTrooper<K, T, P>`**: push streams (WebSockets,
  SSE, event buses) mapped into `StatefulData`, with connection control (`connect`,
  `disconnect`, `connectKeys`, `disconnectKeys`) and `fromStream` constructors.
* **`TrooperMutation<T, P>`**: commands executed in FIFO order with declarative cache
  invalidation (`invalidateOnSuccess`) and cooperative cancellation.
* **`LoadMore<TPage, F, PP>`**: infinite-scroll decorator over a page query with
  `fetchNextPage()`, `retryNextPage()` and `hasNextPage`; `LoadMoreData.items` flattens list
  pages.
* **Accessors**: read-only facades `Accessor<T, P>` and `KeyedAccessor<K, T, P>` for UI layers
  and tests (`trooper.accessor`, `keyed[key]`).

### Controller

* **`TrooperController`**: groups the troopers of a feature and shares cache, queues, storage
  and telemetry between them. Factories: `query`, `cancellableQuery`, `keyedQuery`,
  `cancellableKeyedQuery`, `local`, `keyedLocal`, `keyedLocalBuilder`, `stream`,
  `keyedStream`, `mutation`, `cancellableMutation`, `loadMore`.
* **Lifecycle**: `initialize`, `pause`, `resume`, `recover`, `didChangeDependencies` and
  `dispose` propagate to all managed children; subclasses hook in through `onInit`,
  `onPause`, `onResume`, `onRecover`, `onDependenciesChanged` and `onDispose`.
* **`clearAll()`** removes all cached and persisted data of the controller's troopers,
  for example on logout.

### State model

* **`StatefulData<T>`**: sealed hierarchy for pattern matching: `DataInitial`, `DataLoading`,
  `DataLoaded`, `DataRefreshing`, `DataError` (with `staleData`).
* **Zero-flicker refresh**: `DataRefreshing<T>` extends `DataLoaded<T>`, so UIs keep showing
  data during background refreshes.

### Configuration

* **`TrooperConfig`**: `timeToLive`, `stalePolicy`, `conflictPolicy`, `deduplicate`,
  `storage`, `refreshAfterChangeDependencies`, `timeout` and `retryPolicy`;
  `TrooperConfig.noCache()` for uncached reads.
* **Global default**: `TrooperConfig.setDefault(config)` sets an app-wide default once in
  `main()`, before the first trooper is created; `TrooperConfig.current` reads it and
  `TrooperConfig.resetDefault()` restores it in tests. A trooper uses its own `config`, then
  the controller's `defaultConfig`, then the global default, then `const TrooperConfig()`.
* **`QueryConflictPolicy`**: `forward` (default; superseded callers receive the newer result),
  `cancel` (superseded callers receive a `TrooperCancelledException`) and `parallel`
  (requests run side by side; only the newest response reaches stream, cache and storage).
* **`StalePolicy`**: `keepStaleWhileRevalidate` and `discardStaleOnRefresh`.
* **`RetryPolicy`**: `none()`, `immediate()`, `linear()` and `exponential()` with `maxDelay`,
  `retryWhen` and `jitter` (default `0.5`, so failing clients do not retry in lockstep).

### Caching and persistence

* **`CacheStore`**: L1 cache with time-to-live, optional periodic eviction
  (`evictionInterval`) and an optional size limit with least-recently-used eviction
  (`maxEntries`).
* **`releaseUnwatchedKeys`** on keyed queries and streams drops the in-memory state of keys
  without listeners, while cache and storage are kept.
* **`StorageBackend`**: interface for L2 persistence (`read`, `write`, `delete`,
  `getAllKeys`), with `InMemoryStorageBackend` for tests.
* **`TrooperCodec`**: serialization for L2 with built-in codecs (`string`, `integer`,
  `doublePrecision`, `boolean`, `dateTime`, `json`, `list`, `map`) and `custom`.
* **Stable storage format**: entries are stored in `StorageEnvelope` v1 under versioned keys
  (`trooper:1:<namespace>:<parameter>[:<key>]`). Entries in an unknown format are discarded
  and fetched again; parameters without a stable `toString()` are not persisted
  (`QueryKey.hasStableStorageKey`).
* **Invalidation**: `invalidate()`, `invalidateKey()`, `removeKey()` and `clearAll()` remove
  cached and persisted entries, including entries written in earlier sessions.
* **Sensitive data**: the README section "Persistence & Sensitive Data" shows how to encrypt
  persisted values with a `StorageBackend` decorator.

### Concurrency and resilience

* **`TrooperQueryQueue`**: coalesces identical in-flight reads into one request and applies
  the conflict policy.
* **`TrooperMutationQueue`**: sequential FIFO execution of write operations.
* **`TrooperCancelToken`**: cooperative cancellation for fetches and mutations; a cancelled
  mutation never reports success.
* **Timeouts and retries** per trooper through `TrooperConfig`.

### Errors and lifecycle guarantees

* **`TrooperException`** with `TrooperCancelledException`, `TrooperTimeoutException`,
  `TrooperStorageException` and `TrooperCodecException`.
* **After `dispose()`** reading, writing, emitting, connecting and executing throw a
  `StateError`; snapshots return the last state and cleanup calls are no-ops. `dispose()` is
  idempotent.
* **Callback errors** from side effects (`onData`, `onError`, `onSuccess`, …) and cancel-token
  listeners are reported to the current `Zone` without affecting the request.
* **Persistence errors** are reported as `PersistenceErrorEvent`; Trooper falls back to a
  fresh fetch.

### Observability

* **`TelemetryHub`**: structured events (`RequestStartedEvent`, `RequestCompletedEvent`,
  `RequestErrorEvent`, `CacheHitEvent`, `SWRTriggeredEvent`, `CacheInvalidatedEvent`,
  `DataSetEvent`, `PersistenceErrorEvent`); without a listener, the hot paths skip event
  creation entirely.
* **`TrooperLogger`** and **`ConsoleTrooperLogger`**: pluggable logging; query parameters and
  keys are masked by default (`logParameters: true` prints them).

### Platforms

* Pure Dart without Flutter dependencies; runs on the Dart VM, the web (dart2js and dart2wasm)
  and in Flutter apps.
