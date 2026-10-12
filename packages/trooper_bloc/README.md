# trooper_bloc

Reactive BLoC and Cubit integration for the Trooper data-flow framework.

Combines the architectural power of `flutter_bloc` with Trooper reactive caching, Stale-While-Revalidate (SWR), snapshot-locking, and deduplicated request orchestration.

---

## Features

- **`Tloc<Event, State>`**: Enterprise BLoC base class with event handlers and automatic Trooper source reactivity.
- **`Tubit<State>`**: Lightweight Cubit alternative with full Trooper source reactivity.
- **Snapshot-Locking**: `source.state` remains immutable and frozen throughout the execution of `matchSources`, guaranteeing zero state tearing across asynchronous `await` calls.
- **Microtask Batching**: Coalesces concurrent updates from multiple reactive sources within the same event loop into a single derivation cycle.
- **Restartable Concurrency**: Generational counter tracking automatically discards stale emissions when newer data arrives while an async derivation is in-flight.
- **Fallback Cascades**: Automatic routing to `onAnyError` and `onAnyLoading` whenever `matchSources` returns `MatchResult.unhandled` (or `.unhandled`).
- **Presentation Effects**: `Effects<F>` mixin and `TlocEffectListener` widget for clean, one-off UI events (toasts, snackbars, navigation) without state pollution.
- **100% Test Coverage**: Fully verified test suite with zero warnings or analyzer hints.

---

## Architecture Overview

```
Accessors (Trooper) ──> WatchedHandle ──> TrooperSources Mixin ──> Tloc / Tubit ──> Flutter UI
  (Data Layer)             (Snapshots)        (Derivation Cycle)      (BLoC / Cubit)   (BlocBuilder)
```

In `trooper_bloc`, a `Tloc` or `Tubit` watches one or more Trooper `Accessor` instances. When source data updates, `matchSources` is triggered.

---

## Quick Start

### 1. Define Events & State

```dart
sealed class ProfileEvent extends TlocEvent {
  const ProfileEvent();
}

final class RefreshProfileEvent extends ProfileEvent {
  const RefreshProfileEvent();
}

sealed class ProfileState {
  const ProfileState();
}

final class ProfileLoadingState extends ProfileState {
  const ProfileLoadingState();
}

final class ProfileLoadedState extends ProfileState {
  const ProfileLoadedState({required this.user, required this.settings});
  final User user;
  final Settings settings;
}

final class ProfileErrorState extends ProfileState {
  const ProfileErrorState(this.error);
  final Object error;
}
```

### 2. Implement `Tloc`

```dart
class ProfileTloc extends Tloc<ProfileEvent, ProfileState> {
  ProfileTloc({
    required this.userAccessor,
    required this.settingsAccessor,
  }) : super(const ProfileLoadingState());

  final Accessor<User, ()> userAccessor;
  final Accessor<Settings, ()> settingsAccessor;

  // Declare watched handles
  late final Watched<User> user = watch(userAccessor);
  late final Watched<Settings> settings = watch(settingsAccessor);

  @override
  List<Watched<Object?>> get sources => [user, settings];

  @override
  FutureOr<MatchResult> matchSources(Emit<ProfileState> emit) {
    switch ((user.state, settings.state)) {
      case (DataLoaded(data: final u), DataLoaded(data: final s)):
        emit(ProfileLoadedState(user: u, settings: s));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<ProfileState> emit) {
    emit(const ProfileLoadingState());
  }

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<ProfileState> emit) {
    emit(ProfileErrorState(error));
  }

  @override
  void handlers() {
    on<RefreshProfileEvent>((event, emit) async {
      await userAccessor.refresh();
      await settingsAccessor.refresh();
    });
  }
}
```

---

## Key Concepts

### Snapshot-Locking

In asynchronous architectures, awaiting an HTTP request or database write inside a state derivation can result in race conditions if background streams update while suspended.

`trooper_bloc` solves this with snapshot-locking:
- When `matchSources` begins, every watched source snapshot is frozen (`WatchedHandle.lockSnapshot()`).
- Reading `source.state` after an `await` is guaranteed to return the exact snapshot captured when `matchSources` began.
- When `matchSources` finishes, the snapshot lock is released (`WatchedHandle.unlockSnapshot()`).
- If newer data arrived while `matchSources` was awaiting, generational tracking aborts the stale run and re-executes `matchSources` with fresh snapshots.

### Fallback Cascade

`matchSources` returns `FutureOr<MatchResult>`. When returning `.unhandled`:
1. **Error Check**: If any source is in `DataError`, `onAnyError(error, stackTrace, emit)` is automatically invoked.
2. **Loading Check**: If any source is in `DataLoading` or `DataInitial`, `onAnyLoading(emit)` is automatically invoked.
3. If no fallback applies, the previous state is preserved.

### SWR (Stale-While-Revalidate) Guarantee

When background revalidation occurs, Trooper sources emit `DataRefreshing<T>`. Because `DataRefreshing` retains existing data, `matchSources` continues to match `DataLoaded` patterns and never reverts to a loading spinner during background refreshes.

---

## One-off Presentation Effects

Use the `Effects<F>` mixin to emit one-off side effects (e.g. snackbars, toasts, navigation dialogs) without storing transient events in persistent BLoC state:

```dart
sealed class ProfileEffect {
  const ProfileEffect();
}

final class ShowToastEffect extends ProfileEffect {
  const ShowToastEffect(this.message);
  final String message;
}

class ProfileTloc extends Tloc<ProfileEvent, ProfileState>
    with Effects<ProfileEffect> {
  // ...
  void showSuccess() {
    emitEffect(const ShowToastEffect('Profile updated successfully!'));
  }
}
```

Listen to effects in the widget tree using `TlocEffectListener`:

```dart
TlocEffectListener<ProfileTloc, ProfileEffect>(
  listenWhen: (effect) => effect is ShowToastEffect,
  onEffect: (context, effect) => switch (effect) {
    ShowToastEffect(:final message) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    ),
  },
  child: const ProfileView(),
)
```

---

## Parameterized Accessors

For parameterized queries (such as search filters or pagination), declare `watch(itemAccessor)` to passively observe state updates. Triggering fetches with different parameters from event handlers automatically emits to the single underlying stream and updates `matchSources`:

```dart
class SearchTloc extends Tloc<SearchEvent, SearchState> {
  SearchTloc(this.itemAccessor) : super(const SearchInitialState());

  final Accessor<ItemList, ({String query})> itemAccessor;
  late final Watched<ItemList> items = watch(itemAccessor);

  @override
  List<Watched<Object?>> get sources => [items];

  @override
  void handlers() {
    on<SearchQueryChangedEvent>((event, emit) {
      itemAccessor.trigger((query: event.query));
    });
  }
}
```

---

## Testing Utilities

`package:trooper_bloc/testing.dart` exports `FakeAccessor<T, P>`, allowing you to simulate and manipulate accessor states in unit tests without complex mocks:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';

void main() {
  test('emits loaded state when fake resolves', () async {
    final fake = FakeAccessor<String, ()>(initialData: 'cached');
    final bloc = MyTloc(fake);

    await pumpEventQueue();
    expect(bloc.state, isA<MyLoadedState>());

    fake.emitData('fresh');
    await pumpEventQueue();
    expect((bloc.state as MyLoadedState).data, 'fresh');

    await bloc.close();
  });
}
```

---

## License

MIT License. See LICENSE for details.
