import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:trooper_bloc/src/sources/trooper_sources.dart';

/// Base class for reactive Cubits integrating Trooper data sources with `flutter_bloc`.
///
/// Ideal for state-driven screens without custom event queues. State changes are emitted
/// directly and synchronously when sources change.
///
/// ### Example:
/// ```dart
/// class ProfileTubit extends Tubit<ProfileState> {
///   ProfileTubit({required this.userId}) : super(const ProfileLoadingState());
///
///   final String userId;
///   late final Watched<UserProfile> profile;
///
///   @override
///   List<Watched<Object?>> get sources => [
///     profile = watch(store.users[userId]),
///   ];
///
///   @override
///   FutureOr<MatchResult> matchSources(Emit<ProfileState> emit) {
///     switch (profile.state) {
///       case DataLoaded(data: final user):
///         emit(ProfileLoadedState(user));
///         return .handled;
///     }
///     return .unhandled;
///   }
///
///   @override
///   void onAnyLoading(Emit<ProfileState> emit) => emit(const ProfileLoadingState());
///
///   @override
///   void onAnyError(Object error, StackTrace? st, Emit<ProfileState> emit) =>
///       emit(ProfileErrorState(error));
///
///   Future<void> refresh() => store.users.refreshKey(userId);
/// }
/// ```
///
/// ### Extending
/// Extend this class; do not `implements` it. Implementing it is not
/// supported, and new members can be added in minor releases.
abstract class Tubit<State> extends Cubit<State> with TrooperSources<State> {
  /// Creates a [Tubit] initialized with [initialState].
  Tubit(super.initialState) {
    initializeSources();
  }

  @override
  void triggerSourceEvaluation() {
    if (!isClosed) {
      executeSourceEvaluation(emit);
    }
  }

  @override
  void onSourceException(Object error, StackTrace stackTrace) {
    onError(error, stackTrace);
  }

  /// Pauses watched sources (e.g. when app moves to background).
  void pause() => pauseSources();

  /// Resumes watched sources and evaluates state changes.
  void resume() => resumeSources();

  @override
  @mustCallSuper
  Future<void> close() async {
    await disposeSources();
    return super.close();
  }
}
