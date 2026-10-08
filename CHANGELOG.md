# Changelog

All notable changes to the Trooper monorepo and its workspace packages will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-10-08

Initial public release of the Trooper framework monorepo.

### Added

#### Core Framework (`packages/trooper`)
- **`TrooperQuery<T, P>`**: Asynchronous query manager with multi-tier caching, SWR (Stale-While-Revalidate) background revalidation, and automated request deduplication.
- **`KeyedTrooperQuery<K, T, P>`**: Dynamic collection of queries partitioned by entity key `K` with batch reading support (`getAll`, `getMany`).
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
