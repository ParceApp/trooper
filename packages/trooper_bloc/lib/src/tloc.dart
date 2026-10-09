import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:trooper_bloc/src/events.dart';
import 'package:trooper_bloc/src/sources/trooper_sources.dart';

/// Base class for reactive BLoCs integrating Trooper data sources with `flutter_bloc`.
///
/// Ensures type-safe state derivation, snapshot-locking against race conditions,
/// and automatic error/loading cascades.
///
/// ### Example:
/// ```dart
/// sealed class LectureEvent extends TlocEvent {
///   const LectureEvent();
/// }
///
/// class LectureRefreshEvent extends LectureEvent {
///   const LectureRefreshEvent();
/// }
///
/// class LectureTloc extends Tloc<LectureEvent, LectureState> {
///   LectureTloc({required this.lectureId}) : super(const LectureLoadingState());
///
///   final String lectureId;
///
///   late final Watched<Lecture> lecture;
///   late final Watched<List<TimetableEntry>> entries;
///
///   @override
///   List<Watched<Object?>> get sources => [
///     lecture = watch(store.lectures[lectureId]),
///     entries = watch(store.timetableEntries[lectureId]),
///   ];
///
///   @override
///   FutureOr<MatchResult> matchSources(Emit<LectureState> emit) {
///     switch ((lecture.state, entries.state)) {
///       case (DataLoaded(data: final l), DataLoaded(data: final e)):
///         emit(LectureLoadedState(lecture: l, timetableEntries: e));
///         return .handled;
///       default:
///         return .unhandled;
///     }
///   }
///
///   @override
///   void onAnyLoading(Emit<LectureState> emit) => emit(const LectureLoadingState());
///
///   @override
///   void onAnyError(Object error, StackTrace? stackTrace, Emit<LectureState> emit) =>
///       emit(LectureErrorState(error));
///
///   @override
///   void handlers() {
///     on<LectureRefreshEvent>((_, _) => refreshAll());
///   }
/// }
/// ```
abstract class Tloc<Event extends TlocEvent, State>
    extends Bloc<Event, State> with TrooperSources<State> {
  /// Creates a [Tloc] initialized with [initialState].
  Tloc(super.initialState) {
    handlers();
    initializeSources();
  }

  /// Hook where developers register their event handlers via `on<E>((event, emit) => ...)`.
  @protected
  void handlers();

  @override
  void triggerSourceEvaluation() {
    if (!isClosed) {
      executeSourceEvaluation(_emitFromSource);
    }
  }

  void _emitFromSource(State state) {
    if (!isClosed) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(state);
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
