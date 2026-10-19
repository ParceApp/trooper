---
name: trooper-bloc-state-management
description: Guides integrating Trooper reactive data sources with Flutter BLoC and Cubit using trooper_bloc. Covers Tloc, Tubit, watch(), matchSources(), snapshot-locking, microtask batching, one-off presentation Effects, TlocEffectListener, and unit testing with FakeAccessor.
---

# Trooper BLoC State Management Guide

`trooper_bloc` provides high-performance Flutter BLoC and Cubit integration for the Trooper reactive data-flow framework. It bridges Troopers (data, caching, network) with `flutter_bloc` (presentation state, events, UI widgets) with zero-flicker Stale-While-Revalidate (SWR), snapshot-locking against race conditions, microtask batching, and one-off presentation effects.

Note: `package:trooper_bloc/trooper_bloc.dart` re-exports 100% of `package:trooper/trooper.dart`. In projects using `trooper_bloc`, only `trooper_bloc` needs to be declared in `pubspec.yaml`.

## Contents
- [Core Architecture & Philosophy](#core-architecture--philosophy)
- [Component Overview](#component-overview)
- [Tloc: Reactive BLoC](#tloc-reactive-bloc)
- [Tubit: Reactive Cubit](#tubit-reactive-cubit)
- [Source Derivation with matchSources](#source-derivation-with-matchsources)
- [Snapshot-Locking & Microtask Batching](#snapshot-locking--microtask-batching)
- [One-Off Presentation Effects](#one-off-presentation-effects)
- [Critical Rules & Anti-Patterns](#critical-rules--anti-patterns)
- [Step-by-Step Feature Workflow](#step-by-step-feature-workflow)
- [Unit Testing with FakeAccessor](#unit-testing-with-fakeaccessor)
- [Production-Grade Code Examples](#production-grade-code-examples)

---

## Core Architecture & Philosophy

`trooper_bloc` strictly separates data-layer responsibilities from presentation state:

```
[Remote API / Storage]
        │
        ▼
[Trooper / TrooperController] ── (Manages cache, TTL, SWR, deduplication, websockets)
        │
        ▼ (Exposes Accessors)
[Tloc / Tubit]               ── (Watches sources, derives UI state, handles UI events)
        │
        ▼ (Emits State & Effects)
[Flutter UI]                 ── (BlocBuilder, BlocListener, TlocEffectListener)
```

1. **Separation of Concerns**: Troopers handle HTTP calls, L1/L2 caches, TTL expiry, SWR revalidation, and WebSocket streams. BLoCs and Cubits never touch storage or raw network clients directly.
2. **Accessors over Raw Troopers**: `Tloc` and `Tubit` consume data sources through `Accessor<T, P>` or `KeyedAccessor<K, T, P>`.
3. **Reactive Derivation**: Instead of manually wiring stream subscriptions and combining states, developers declare `sources` and define `matchSources`. The framework automatically evaluates dependencies and emits updates.
4. **BLoC-Conformant Transitions**: All state changes triggered by source updates in `Tloc` flow through an internal BLoC event (not exported, visible by its `toString()`), ensuring full auditability in `BlocObserver` (`onTransition`, `onChange`).
5. **Zero-Flicker SWR**: Because `DataRefreshing<T>` extends `DataLoaded<T>`, matching on `case DataLoaded(:final data)` keeps cached data on screen while background revalidation executes seamlessly.

---

## Component Overview

| Component | Role | When to Use |
|---|---|---|
| [`Tloc<Event, State>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/src/tloc.dart) | Reactive BLoC | Complex screens requiring domain events, event queues, or concurrent user actions |
| [`Tubit<State>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/src/tubit.dart) | Reactive Cubit | State-driven views where state derives directly from sources without custom event queues |
| [`TrooperSources<State>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/src/sources/trooper_sources.dart) | Core Reactive Mixin | Implements `watch()`, `matchSources()`, snapshot-locking, and loading/error fallbacks |
| [`Watched<T>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/src/sources/watched.dart) | Watched Source Handle | Read-only snapshot of an observed accessor: `.state`, `.hasData`, `.isLoading`, `.isError`, `.dataOrNull` |
| [`Effects<F>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/src/effects/effects.dart) | Presentation Effect Mixin | Emits one-off UI events (toasts, snackbars, navigation) without polluting state |
| [`TlocEffectListener<B, F>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/src/widgets/tloc_effect_listener.dart) | Flutter Effect Widget | Listens to one-off effects from `Effects<F>` without causing widget rebuilds |
| [`FakeAccessor<T, P>`](file:///Users/hannes/Developer/trooper/packages/trooper_bloc/lib/testing.dart) | Testing Utility | High-level test double for simulating accessor states in fast, deterministic unit tests |

---

## Tloc: Reactive BLoC

`Tloc<Event extends TlocEvent, State>` combines `flutter_bloc.Bloc` with `TrooperSources<State>`.

### Class Skeleton

```dart
import 'dart:async';
import 'package:trooper_bloc/trooper_bloc.dart';

// 1. Events must extend TlocEvent
sealed class FeedEvent extends TlocEvent {
  const FeedEvent();
}

final class FeedRefreshRequested extends FeedEvent {
  const FeedRefreshRequested();
}

// 2. Sealed state hierarchy
sealed class FeedState {
  const FeedState();
}

final class FeedLoadingState extends FeedState {
  const FeedLoadingState();
}

final class FeedLoadedState extends FeedState {
  const FeedLoadedState({required this.articles, required this.isRefreshing});
  final List<Article> articles;
  final bool isRefreshing;
}

final class FeedErrorState extends FeedState {
  const FeedErrorState(this.error);
  final Object error;
}

// 3. Tloc Implementation
class FeedTloc extends Tloc<FeedEvent, FeedState> {
  FeedTloc({required FeedController controller})
    : _controller = controller,
      super(const FeedLoadingState());

  final FeedController _controller;

  // Declare watched source handles
  late final Watched<List<Article>> _articles;

  @override
  List<Watched<Object?>> get sources => [
    _articles = watch(_controller.articles, eager: true),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<FeedState> emit) {
    switch (_articles.state) {
      case DataLoaded(:final data, :final isRefreshing):
        emit(FeedLoadedState(articles: data, isRefreshing: isRefreshing));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<FeedState> emit) => emit(const FeedLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<FeedState> emit) =>
      emit(FeedErrorState(error));

  @override
  void handlers() {
    on<FeedRefreshRequested>((event, emit) async {
      await _controller.articles.refresh(());
    });
  }
}
```

### Key Lifecycle Rules for Tloc
- Event handlers are declared inside `void handlers()`, never directly in the constructor body.
- Source subscriptions are declared in `List<Watched<Object?>> get sources`.
- All `sources` must be initialized using `watch(accessor)`.
- Custom events must extend `TlocEvent`.

---

## Tubit: Reactive Cubit

`Tubit<State>` combines `flutter_bloc.Cubit` with `TrooperSources<State>`. It is ideal for views that only derive state from sources and invoke methods rather than dispatching formal events.

### Class Skeleton

```dart
import 'dart:async';
import 'package:trooper_bloc/trooper_bloc.dart';

class UserProfileTubit extends Tubit<UserProfileState> {
  UserProfileTubit({required this.userId, required UserController controller})
    : _controller = controller,
      super(const UserProfileLoadingState());

  final String userId;
  final UserController _controller;

  late final Watched<UserProfile> _profile;
  late final Watched<UserSettings> _settings;

  @override
  List<Watched<Object?>> get sources => [
    _profile = watch(_controller.users[userId], eager: true),
    _settings = watch(_controller.settings, eager: true),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<UserProfileState> emit) {
    switch ((_profile.state, _settings.state)) {
      case (DataLoaded(data: final profile), DataLoaded(data: final settings)):
        emit(UserProfileLoadedState(profile: profile, settings: settings));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<UserProfileState> emit) =>
      emit(const UserProfileLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<UserProfileState> emit) =>
      emit(UserProfileErrorState(error));

  Future<void> refresh() async {
    await Future.wait([
      _controller.users[userId].refresh(()),
      _controller.settings.refresh(()),
    ]);
  }
}
```

---

## Source Derivation with matchSources

`matchSources(Emit<State> emit)` is called whenever one or more watched sources emit an updated state.

### Return Values: `MatchResult`
- `MatchResult.handled` (or concise shorthand `.handled`): Indicates that the current combination of sources was processed and a state was emitted.
- `MatchResult.unhandled` (or `.unhandled`): Indicates that the combination was not handled. The framework automatically falls back to:
  1. `onAnyError(error, stackTrace, emit)` if any source is in `DataError`.
  2. `onAnyLoading(emit)` if any source is in `DataLoading` or `DataInitial`.

### Multi-Source Pattern Matching
Dart 3 record patterns enable concise, exhaustive matching across multiple sources:

```dart
@override
FutureOr<MatchResult> matchSources(Emit<DashboardState> emit) {
  switch ((userSource.state, metricsSource.state, alertsSource.state)) {
    // Both user and metrics are ready; alerts are optional
    case (
      DataLoaded(data: final user),
      DataLoaded(data: final metrics),
      final alertsState,
    ):
      emit(
        DashboardLoadedState(
          user: user,
          metrics: metrics,
          alerts: alertsState.dataOrNull ?? const [],
        ),
      );
      return .handled;

    default:
      return .unhandled;
  }
}
```

---

## Snapshot-Locking & Microtask Batching

`trooper_bloc` includes two built-in concurrency guarantees:

### 1. Snapshot-Locking
When `matchSources` executes, every `watchedHandle.state` is frozen to an immutable snapshot taken at the start of that evaluation cycle.
- Even if `matchSources` performs asynchronous work (`await something()`), the state of watched sources will never tear or change unexpectedly midway through execution.
- If a source emits a newer value while `matchSources` is awaiting asynchronous operations, the stale evaluation is automatically aborted (restartable concurrency) and a fresh cycle is scheduled with the newest snapshots.

### 2. Microtask Batching
When multiple watched sources emit in the same microtask (e.g. initializing multiple cached troopers simultaneously), `trooper_bloc` batches the updates into a single call to `matchSources`. This eliminates redundant rebuilds and intermediate invalid UI states.

---

## One-Off Presentation Effects

For actions that should occur exactly once (showing a SnackBar, showing a modal bottom sheet, or navigating to another route), do not add ephemeral boolean flags to your BLoC state. Instead, use the `Effects<F>` mixin.

### 1. Define the Effect Hierarchy

```dart
sealed class OrderEffect {
  const OrderEffect();
}

final class ShowOrderSuccessSnackBar extends OrderEffect {
  const ShowOrderSuccessSnackBar(this.orderId);
  final String orderId;
}

final class NavigateToReceiptScreen extends OrderEffect {
  const NavigateToReceiptScreen(this.orderId);
  final String orderId;
}
```

### 2. Add the Mixin to Tloc or Tubit

```dart
class OrderTloc extends Tloc<OrderEvent, OrderState>
    with Effects<OrderEffect> {
  OrderTloc({required OrderController controller})
    : _controller = controller,
      super(const OrderInitialState());

  final OrderController _controller;

  @override
  List<Watched<Object?>> get sources => [];

  @override
  FutureOr<MatchResult> matchSources(Emit<OrderState> emit) => .unhandled;

  @override
  void handlers() {
    on<SubmitOrderEvent>((event, emit) async {
      emit(const OrderSubmittingState());
      try {
        final orderId = await _controller.submitOrder(event.payload);
        emit(OrderSuccessState(orderId));
        emitEffect(ShowOrderSuccessSnackBar(orderId));
        emitEffect(NavigateToReceiptScreen(orderId));
      } catch (error) {
        emit(OrderFailureState(error));
      }
    });
  }
}
```

### 3. Consume Effects in Flutter UI with TlocEffectListener

```dart
Widget build(BuildContext context) {
  return BlocProvider(
    create: (context) => OrderTloc(controller: context.read<OrderController>()),
    child: TlocEffectListener<OrderTloc, OrderEffect>(
      onEffect: (context, effect) => switch (effect) {
        ShowOrderSuccessSnackBar(:final orderId) =>
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order #$orderId placed successfully!')),
          ),
        NavigateToReceiptScreen(:final orderId) =>
          Navigator.of(context).pushNamed('/receipt', arguments: orderId),
      },
      child: const OrderFormView(),
    ),
  );
}
```

---

## Critical Rules & Anti-Patterns

### Rules
1. **Never make HTTP/database requests in Tloc/Tubit**: Place data-fetching logic inside Troopers or Repositories. BLoCs only orchestrate Troopers and derive UI state.
2. **Define event handlers inside `handlers()`**: Never call `on<Event>` inside the constructor body of a `Tloc`. Put all event handler registrations in `void handlers()`.
3. **Always declare watched sources in `sources`**: Every handle created via `watch(...)` must be included in the `sources` getter list.
4. **Use `late final` for watched handles**: Declare `late final Watched<T> mySource;` and assign it inside the `sources` getter: `[mySource = watch(...)]`.
5. **Always return `.handled` or `.unhandled` from `matchSources`**: Never return arbitrary values or omit the return statement.
6. **Use `DataLoaded` pattern matching for SWR**: `DataRefreshing` extends `DataLoaded`. Matching `case DataLoaded(:final data)` seamlessly maintains loaded UI while background refreshing occurs.
7. **Use `Effects<F>` for one-shot UI actions**: Never use state flags like `isSuccess: true` that require immediate reset events.
8. **Import what is not re-exported**: `trooper_bloc` re-exports `package:trooper/trooper.dart` only. Import `dart:async` for `FutureOr` (needed for `matchSources`) and `package:flutter_bloc/flutter_bloc.dart` for `Emitter`, `BlocProvider` and `BlocBuilder`.
9. **Pass `()` explicitly**: Accessors with `P == ()` take the empty record: `accessor.refresh(())`, `keyed[id].get(())`. Inside `watch(accessor)` the `()` is filled in automatically.
10. **Extend, never implement** `Tloc`, `Tubit` and `TlocEvent`. Concrete troopers are `final`: in tests, depend on `Accessor` and use `FakeAccessor` instead of mocking troopers.

### Anti-Patterns to Avoid
- **Anti-Pattern**: Calling `emit()` inside an asynchronous callback in `handlers()` without using the `emit` parameter.
- **Anti-Pattern**: Subscribing manually to `trooper.stream.listen(...)` inside a BLoC. Always use `watch(accessor)`.
- **Anti-Pattern**: Omitting `super.close()` when overriding `close()` in `Tloc` or `Tubit`.

---

## Step-by-Step Feature Workflow

When building a new feature with `trooper` and `trooper_bloc`:

1. **Model Data in Troopers**:
   - Define a `TrooperController` containing `QueryTrooper`, `KeyedQueryTrooper`, `LocalTrooper`, or `StreamTrooper`.
   - Configure caching, TTL, and refresh policies.
2. **Define Presentation Contract**:
   - Create sealed class hierarchies for `State`, `Event` (extending `TlocEvent`), and optional `Effects`.
3. **Implement Tloc or Tubit**:
   - Extend `Tloc<Event, State>` or `Tubit<State>`.
   - In `sources`, call `watch()` on the required accessors.
   - Implement `matchSources(emit)` with pattern matching.
   - Implement `onAnyLoading(emit)` and `onAnyError(error, stackTrace, emit)` fallbacks.
   - Register user event handlers in `handlers()`.
4. **Build Flutter Widgets**:
   - Provide the BLoC using `BlocProvider`.
   - Rebuild UI using `BlocBuilder` or `BlocConsumer`.
   - Listen to presentation effects using `TlocEffectListener`.
5. **Write Unit Tests**:
   - Use `FakeAccessor` from `package:trooper_bloc/testing.dart` to simulate data emissions deterministically.

---

## Unit Testing with FakeAccessor

`trooper_bloc` provides `FakeAccessor<T, P>` in `package:trooper_bloc/testing.dart`. It allows testing `Tloc` and `Tubit` in complete isolation without mocking network requests or initializing Trooper caches.

### Example Unit Test

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trooper_bloc/testing.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

// Test Events & States
sealed class CounterEvent extends TlocEvent {
  const CounterEvent();
}

final class IncrementRequested extends CounterEvent {
  const IncrementRequested();
}

sealed class CounterState {
  const CounterState();
}

final class CounterLoading extends CounterState {
  const CounterLoading();
}

final class CounterReady extends CounterState {
  const CounterReady(this.value);
  final int value;
}

final class CounterError extends CounterState {
  const CounterError(this.message);
  final String message;
}

// BLoC Under Test
class CounterTloc extends Tloc<CounterEvent, CounterState> {
  CounterTloc(this.fakeAccessor) : super(const CounterLoading());

  final FakeAccessor<int, ()> fakeAccessor;
  late final Watched<int> _count;

  @override
  List<Watched<Object?>> get sources => [_count = watch(fakeAccessor)];

  @override
  MatchResult matchSources(Emit<CounterState> emit) {
    switch (_count.state) {
      case DataLoaded(data: final val):
        emit(CounterReady(val));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<CounterState> emit) => emit(const CounterLoading());

  @override
  void onAnyError(Object error, StackTrace? st, Emit<CounterState> emit) =>
      emit(CounterError(error.toString()));

  @override
  void handlers() {
    on<IncrementRequested>((event, emit) {
      final currentVal = _count.dataOrNull ?? 0;
      fakeAccessor.emitData(currentVal + 1);
    });
  }
}

void main() {
  group('CounterTloc Unit Tests', () {
    late FakeAccessor<int, ()> fakeAccessor;

    setUp(() {
      fakeAccessor = FakeAccessor<int, ()>();
    });

    blocTest<CounterTloc, CounterState>(
      'emits CounterReady when fake accessor emits data',
      build: () => CounterTloc(fakeAccessor),
      act: (bloc) => fakeAccessor.emitData(42),
      expect: () => [
        isA<CounterReady>().having((s) => s.value, 'value', 42),
      ],
    );

    blocTest<CounterTloc, CounterState>(
      'falls back to onAnyError when fake accessor emits error',
      build: () => CounterTloc(fakeAccessor),
      act: (bloc) => fakeAccessor.emitError('Server offline'),
      expect: () => [
        isA<CounterError>().having((s) => s.message, 'message', contains('Server offline')),
      ],
    );

    blocTest<CounterTloc, CounterState>(
      'increments value upon IncrementRequested event',
      build: () => CounterTloc(fakeAccessor),
      seed: () => const CounterReady(10),
      setUp: () => fakeAccessor.emitData(10),
      act: (bloc) => bloc.add(const IncrementRequested()),
      expect: () => [
        isA<CounterReady>().having((s) => s.value, 'value', 11),
      ],
    );
  });
}
```

---

## Production-Grade Code Examples

### Full Feature: Weather Dashboard with Multiple Sources and Effects

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

// --- Domain Models ---
class WeatherReport {
  const WeatherReport({required this.city, required this.tempC});
  final String city;
  final double tempC;
}

class AirQualityReport {
  const AirQualityReport({required this.aqiIndex});
  final int aqiIndex;
}

// --- Data Controller (Trooper) ---
class WeatherDataController extends TrooperController {
  late final weather = query<WeatherReport, ({String city})>(
    namespace: 'weather',
    fetch: (params) async {
      // Simulated network fetch
      return WeatherReport(city: params.city, tempC: 22.5);
    },
    config: const TrooperConfig(timeToLive: Duration(minutes: 10)),
  );

  late final airQuality = query<AirQualityReport, ({String city})>(
    namespace: 'airQuality',
    fetch: (params) async {
      return const AirQualityReport(aqiIndex: 42);
    },
    config: const TrooperConfig(timeToLive: Duration(minutes: 10)),
  );
}

// --- BLoC Events ---
sealed class WeatherEvent extends TlocEvent {
  const WeatherEvent();
}

final class RefreshWeatherRequested extends WeatherEvent {
  const RefreshWeatherRequested();
}

// --- Presentation Effects ---
sealed class WeatherEffect {
  const WeatherEffect();
}

final class ShowWarningToast extends WeatherEffect {
  const ShowWarningToast(this.message);
  final String message;
}

// --- BLoC States ---
sealed class WeatherState {
  const WeatherState();
}

final class WeatherLoadingState extends WeatherState {
  const WeatherLoadingState();
}

final class WeatherLoadedState extends WeatherState {
  const WeatherLoadedState({
    required this.weather,
    required this.airQuality,
    required this.isRefreshing,
  });

  final WeatherReport weather;
  final AirQualityReport airQuality;
  final bool isRefreshing;
}

final class WeatherErrorState extends WeatherState {
  const WeatherErrorState(this.errorMessage);
  final String errorMessage;
}

// --- Tloc Implementation ---
class WeatherTloc extends Tloc<WeatherEvent, WeatherState>
    with Effects<WeatherEffect> {
  WeatherTloc({
    required this.city,
    required WeatherDataController controller,
  }) : _controller = controller,
       super(const WeatherLoadingState());

  final String city;
  final WeatherDataController _controller;

  late final Watched<WeatherReport> _weather;
  late final Watched<AirQualityReport> _airQuality;

  @override
  List<Watched<Object?>> get sources => [
    _weather = watch(
      _controller.weather,
      initialParameter: (city: city),
      eager: true,
    ),
    _airQuality = watch(
      _controller.airQuality,
      initialParameter: (city: city),
      eager: true,
    ),
  ];

  @override
  FutureOr<MatchResult> matchSources(Emit<WeatherState> emit) {
    switch ((_weather.state, _airQuality.state)) {
      case (
        DataLoaded(data: final weather, isRefreshing: final isWeatherRefreshing),
        DataLoaded(data: final airQuality, isRefreshing: final isAirRefreshing),
      ):
        final isRefreshing = isWeatherRefreshing || isAirRefreshing;
        emit(
          WeatherLoadedState(
            weather: weather,
            airQuality: airQuality,
            isRefreshing: isRefreshing,
          ),
        );

        if (airQuality.aqiIndex > 100) {
          emitEffect(const ShowWarningToast('High pollution detected in your area!'));
        }
        return .handled;

      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<WeatherState> emit) => emit(const WeatherLoadingState());

  @override
  void onAnyError(Object error, StackTrace? stackTrace, Emit<WeatherState> emit) =>
      emit(WeatherErrorState(error.toString()));

  @override
  void handlers() {
    on<RefreshWeatherRequested>((event, emit) async {
      await Future.wait([
        _controller.weather.refresh((city: city)),
        _controller.airQuality.refresh((city: city)),
      ]);
    });
  }
}

// --- Flutter UI Integration ---
class WeatherScreen extends StatelessWidget {
  const WeatherScreen({required this.city, super.key});

  final String city;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WeatherTloc(
        city: city,
        controller: context.read<WeatherDataController>(),
      ),
      child: TlocEffectListener<WeatherTloc, WeatherEffect>(
        onEffect: (context, effect) => switch (effect) {
          ShowWarningToast(:final message) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.orange,
            ),
          ),
        },
        child: Scaffold(
          appBar: AppBar(title: Text('Weather: $city')),
          body: BlocBuilder<WeatherTloc, WeatherState>(
            builder: (context, state) => switch (state) {
              WeatherLoadingState() => const Center(child: CircularProgressIndicator()),
              WeatherErrorState(:final errorMessage) => Center(
                child: Text('Error: $errorMessage'),
              ),
              WeatherLoadedState(
                :final weather,
                :final airQuality,
                :final isRefreshing,
              ) =>
                RefreshIndicator(
                  onRefresh: () async {
                    context.read<WeatherTloc>().add(const RefreshWeatherRequested());
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (isRefreshing) const LinearProgressIndicator(),
                      Card(
                        child: ListTile(
                          title: Text('${weather.tempC}°C'),
                          subtitle: Text('City: ${weather.city}'),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          title: Text('AQI: ${airQuality.aqiIndex}'),
                          subtitle: const Text('Air Quality Index'),
                        ),
                      ),
                    ],
                  ),
                ),
            },
          ),
        ),
      ),
    );
  }
}
```
