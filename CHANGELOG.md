# Changelog

All notable changes to the Trooper monorepo and its workspace packages will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed (breaking): API freeze for 1.0

Both packages prepare their public API for the 1.0 freeze: internals hidden, class modifiers
set, redundant APIs removed, uniform behavior after `dispose()`, slimmer `StorageBackend`,
open-ended exception and event catalogues, no re-export of `Emitter`/`FutureOr` from
`trooper_bloc`. Migration tables are in `packages/trooper/CHANGELOG.md` and
`packages/trooper_bloc/CHANGELOG.md`; decisions in `docs/audit/api-freeze-decisions.md`; the
API baseline in `docs/api/`.

### Added

#### Core Framework (`packages/trooper`)
- **`LoadMore<TPage, F, PP>`**: Load-more (infinite scroll) decorator over an existing page query with `fetchNextPage()`, `retryNextPage()`, and `hasNextPage`. All type arguments are inferred from the wrapped query.
- **`LoadMoreData<TPage, PP>`**: Accumulated pages plus next-page status (`isFetchingNextPage`, `nextPageError`) so the feed stays `DataLoaded` while loading more.
- **`TrooperController.loadMore(...)`**: Factory that creates a managed `LoadMore` feed.
- **Docs**: New pagination guide covering classic pages (`TrooperConfig.noCache()`) and load more.

---

## [0.1.0] - 2026-10-08

Initial public release of the Trooper framework monorepo.

### Added

#### Core Framework (`packages/trooper`)
- **`QueryTrooper<T, P>`**: Asynchronous query manager with multi-tier caching, SWR (Stale-While-Revalidate) background revalidation, and automated request deduplication.
- **`KeyedQueryTrooper<K, T, P>`**: Dynamic collection of queries partitioned by entity key `K` with batch reading support (`getAll`, `getMany`).
- **`LocalTrooper<T, P>`**: In-memory reactive state manager with optional persistent L2 storage synchronization.
- **`KeyedLocalTrooper<K, T, P>`**: In-memory state collections partitioned dynamically by key with bulk operations (`setAll`, `updateAll`, `resetKeys`, `getAll`).
- **`StreamTrooper<T, P>`**: Push stream bridge for WebSockets, Server-Sent Events, and broadcast channels with connection lifecycle management.
- **`KeyedStreamTrooper<K, T, P>`**: Multi-channel push streams partitioned dynamically by key with batch connection support (`connectKeys`, `disconnectKeys`, `getAll`).
- **`TrooperMutation<T, P>`**: Command operations with sequential execution queuing and declarative cache invalidation (`invalidateOnSuccess`).
- **`TrooperController`**: Architectural composition unit managing feature queries, mutations, shared caches, and lifecycle propagation.

#### Concurrency & Resilience
- **`TrooperQueryQueue`**: Request coalescing engine supporting conflict policies (`forward`, `cancel`, `parallel`).
- **`TrooperMutationQueue`**: Sequential FIFO execution queue preventing race conditions.
- **`TrooperCancelToken`**: Cooperative cancellation token with listener registration and exception propagation.
- **`RetryPolicy`**: Configurable linear, immediate, and exponential retry strategies.
- **Timeouts**: Granular timeout support via `TrooperConfig(timeout: ...)`.

#### State Model & Caching
- **`StatefulData<T>`**: Sealed algebraic data hierarchy (`DataInitial`, `DataLoading`, `DataLoaded`, `DataRefreshing`, `DataError`).
- **Zero-Flicker SWR**: `DataRefreshing<T>` extends `DataLoaded<T>` to maintain active data representation during background fetches.
- **`CacheStore`**: In-memory L1 cache with TTL expiration, sweep eviction, and namespace invalidation.
- **`StorageEnvelope` & `StorageBackend`**: Pluggable L2 persistent storage with schema versioning and expiration metadata.
- **`TrooperCodec`**: Extensible codecs for model serialization (JSON, primitives, collections).

#### Telemetry & Diagnostics
- **`TelemetryHub`**: Zero-allocation diagnostic event pipeline emitting structured `TrooperEvent` instances.
- **`ConsoleTrooperLogger`**: Formatted console logging for debugging and audit trails.

#### Testing & Quality
- **172 Unit & Integration Tests**: 100% pass rate with **83.8%** code coverage.
- **Benchmarks**: Benchmark suite measuring throughput and latency for query and cache operations.
- **Static Analysis**: 0 issues under strict `very_good_analysis`.

#### Flutter BLoC Integration (`packages/trooper_bloc`)
- **`Tloc<Event, State>`**: Enterprise BLoC base class combining `flutter_bloc` with Trooper reactive caching and snapshot-locking.
- **`Tubit<State>`**: Lightweight Cubit alternative for reactive state derivation without events.
- **`TrooperSources`**: Core derivation mixin with snapshot-locking, microtask batching, and restartable async concurrency.
- **`watch`**: Declarative source watching with passive and parameterized observation.
- **`MatchResult`**: Type-safe derivation result (`.handled`, `.unhandled`) with automated loading and error fallback cascades.
- **`Effects<F>` & `TlocEffectListener`**: One-off presentation side-effects pipeline for snackbars, toasts, and navigation.
- **`FakeAccessor<T, P>`**: In-memory test utility for testing BLoC derivation states.
- **100% Test Coverage**: 40 unit and widget tests with zero warnings or analyzer hints.
