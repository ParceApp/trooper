# Changelog

All notable changes to this package are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this package follows
[Semantic Versioning](https://semver.org/).

## 1.0.0

First release of Trooper BLoC, the BLoC and Cubit integration for the Trooper reactive data-flow
framework. Requires `trooper: ^1.0.0` and `flutter_bloc: ^9.1.1`.
The public API is stable and follows semantic versioning (see `docs/DEPRECATION.md` in the
repository).

### BLoC and Cubit integration

* **`Tloc<Event extends TlocEvent, State>`**: BLoC base class that derives its state from
  Trooper sources.
* **`Tubit<State>`**: Cubit counterpart for state derivation without explicit events.
* **`TlocEvent`**: base class for domain events handled by a `Tloc`.

### Reactive sources and derivation

* **`TrooperSources<S>`**: derivation mixin with microtask batching (several source updates in
  one event loop lead to one derivation) and restartable, generation-based evaluation.
* **`watch(accessor, initialParameter: …, eager: …)`**: registers a Trooper accessor as a
  source and returns a `Watched<T>`.
* **`Watched<T>`**: synchronous view of a source's state (`state`, `hasData`, `isLoading`,
  `isError`, `dataOrNull`).
* **Snapshot locking**: source states stay frozen while `matchSources` runs, also across
  `await`, so a derivation never mixes old and new states.
* **`MatchResult`**: `handled` or `unhandled`; unhandled derivations fall back to
  `onAnyError` and `onAnyLoading`.
* **Zero-flicker refresh**: `DataRefreshing` matches `DataLoaded` patterns, so background
  refreshes never show a loading state.

### Presentation effects

* **`Effects<F>`**: mixin for one-off effects such as snackbars, dialogs or navigation
  (`emitEffect`, `effects` stream) that do not belong in state.
* **`TlocEffectListener`**: widget that listens to `Effects`, with optional `listenWhen` and
  `context.read` fallback.

### Testing

* **`FakeAccessor<T, P>`** (`package:trooper_bloc/testing.dart`): in-memory accessor for unit
  tests that emits initial, loading, loaded, refreshing and error states and counts calls.

### Packaging

* Re-exports `package:trooper/trooper.dart`; `trooper_bloc` always shares the major version
  of `trooper`. `flutter_bloc` is not re-exported: import
  `package:flutter_bloc/flutter_bloc.dart` for `BlocProvider`, `BlocBuilder` and `Emitter`.
