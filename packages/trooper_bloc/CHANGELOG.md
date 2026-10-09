## 0.1.0

Initial public release of Trooper BLoC, high-performance Flutter BLoC and Cubit integration for the Trooper reactive data-flow framework.

### Core BLoC & Cubit Integration
* **`Tloc<Event extends TlocEvent, State>`**: Enterprise BLoC base class combining `flutter_bloc` with Trooper reactive caching and snapshot-locking.
* **`Tubit<State>`**: Lightweight Cubit alternative for reactive state derivation without explicit events.
* **`TlocEvent`**: Base class for domain events processed by `Tloc`.

### Reactive Sources & Derivation
* **`TrooperSources<S>`**: Core derivation mixin providing microtask batching, generation-based restartable concurrency, and automatic lifecycle management.
* **`watch(accessor)` & `watchWith(accessor, parameter)`**: Declarative registration of watched sources with strong typing.
* **`Watched<T>` & `DynamicWatched<T, P>`**: Reactive source handles providing synchronous state inspection and dynamic parameter or source switching.
* **Snapshot-Locking**: Freezes `source.state` throughout `matchSources` evaluation, preventing state tearing across asynchronous `await` steps.
* **`MatchResult`**: Type-safe derivation result (`.handled`, `.unhandled`) with automatic cascade to `onAnyError` and `onAnyLoading`.
* **Zero-Flicker SWR Guarantee**: Preserves existing rendered state during background refreshes without reverting to loading indicators.

### UI & Presentation Effects
* **`Effects<F>`**: Mixin for emitting one-off presentation side-effects (toasts, snackbars, navigation) without polluting persistent state.
* **`TlocEffectListener`**: Flutter widget listening to `Effects` streams with optional `listenWhen` filtering and automatic `context.read<B>()` fallback.

### Testing Utilities
* **`FakeAccessor<T, P>`**: In-memory test accessor for simulating loading, loaded, refreshing, and error states with call counters in unit tests.
