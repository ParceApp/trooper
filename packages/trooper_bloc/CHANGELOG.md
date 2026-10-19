## 1.0.0

First stable release, requires `trooper: ^1.0.0`. The public API is frozen and follows
semantic versioning.
From 1.0.0 on, public symbols are deprecated for at least one minor release before they are
removed in the next major release; see `docs/DEPRECATION.md`.

### Breaking: API freeze for 1.0

* `trooper_bloc` no longer re-exports `Emitter` (`flutter_bloc`) or `FutureOr` (`dart:async`).
  Add `import 'dart:async';` where you write `FutureOr<MatchResult> matchSources(...)`, and
  `import 'package:flutter_bloc/flutter_bloc.dart';` where you use `Emitter`, `BlocProvider`
  or `BlocBuilder`.
* `WatchedHandle`, `WatchedUpdateCallback` and `TlocSourceUpdateEvent` are no longer exported.
  Use `Watched<T>` (the return type of `watch`). The internal event still reaches
  `BlocObserver.onEvent`/`onTransition`.
* `FakeAccessor` is `final`.
* `Tloc`, `Tubit` and `TlocEvent` are meant to be extended, not implemented; new members can
  be added in minor releases.
* **Versioning rule**: `trooper_bloc` re-exports all of `package:trooper/trooper.dart` and
  always shares its major version. A major release of `trooper` is a major release of
  `trooper_bloc`; minor and patch releases of `trooper` only add to the re-exported API.
* Includes every breaking change of `trooper` (see its CHANGELOG, "Migration from 0.1.x"),
  for example explicit `()` arguments: `accessor.refresh(())`.

## 0.1.0-beta.1

Initial public release of Trooper BLoC, high-performance Flutter BLoC and Cubit integration for the Trooper reactive data-flow framework.

### Core BLoC & Cubit Integration
* **`Tloc<Event extends TlocEvent, State>`**: Enterprise BLoC base class combining `flutter_bloc` with Trooper reactive caching and snapshot-locking.
* **`Tubit<State>`**: Lightweight Cubit alternative for reactive state derivation without explicit events.
* **`TlocEvent`**: Base class for domain events processed by `Tloc`.

### Reactive Sources & Derivation
* **`TrooperSources<S>`**: Core derivation mixin providing microtask batching, generation-based restartable concurrency, and automatic lifecycle management.
* **`watch(accessor, [parameter])`**: Declarative registration of watched sources with strong typing.
* **`Watched<T>`**: Reactive source handles providing synchronous snapshot state inspection, pattern matching, and SWR guarantees.
* **Snapshot-Locking**: Freezes `source.state` throughout `matchSources` evaluation, preventing state tearing across asynchronous `await` steps.
* **`MatchResult`**: Type-safe derivation result (`.handled`, `.unhandled`) with automatic cascade to `onAnyError` and `onAnyLoading`.
* **Zero-Flicker SWR Guarantee**: Preserves existing rendered state during background refreshes without reverting to loading indicators.

### UI & Presentation Effects
* **`Effects<F>`**: Mixin for emitting one-off presentation side-effects (toasts, snackbars, navigation) without polluting persistent state.
* **`TlocEffectListener`**: Flutter widget listening to `Effects` streams with optional `listenWhen` filtering and automatic `context.read<B>()` fallback.

### Testing Utilities
* **`FakeAccessor<T, P>`**: In-memory test accessor for simulating loading, loaded, refreshing, and error states with call counters in unit tests.
