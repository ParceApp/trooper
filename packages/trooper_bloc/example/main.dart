import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trooper_bloc/trooper_bloc.dart';

// ---------------------------------------------------------------------------
// 1. Domain Models
// ---------------------------------------------------------------------------

class Lecture {
  const Lecture({
    required this.id,
    required this.title,
    required this.isBookmarked,
  });
  final String id;
  final String title;
  final bool isBookmarked;
}

// ---------------------------------------------------------------------------
// 2. Events & States
// ---------------------------------------------------------------------------

sealed class LectureEvent extends TlocEvent {
  const LectureEvent();
}

final class ToggleBookmarkEvent extends LectureEvent {
  const ToggleBookmarkEvent();
}

final class RefreshLectureEvent extends LectureEvent {
  const RefreshLectureEvent();
}

sealed class LectureState {
  const LectureState();
}

final class LectureLoadingState extends LectureState {
  const LectureLoadingState();
}

final class LectureLoadedState extends LectureState {
  const LectureLoadedState({required this.lecture, required this.isBookmarked});
  final Lecture lecture;
  final bool isBookmarked;
}

final class LectureErrorState extends LectureState {
  const LectureErrorState(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// 3. One-off Presentation Effects
// ---------------------------------------------------------------------------

sealed class LectureEffect {
  const LectureEffect();
}

final class ShowToastEffect extends LectureEffect {
  const ShowToastEffect(this.message);
  final String message;
}

// ---------------------------------------------------------------------------
// 4. Tloc Implementation (BLoC + Trooper Sources)
// ---------------------------------------------------------------------------

class LectureTloc extends Tloc<LectureEvent, LectureState>
    with Effects<LectureEffect> {
  LectureTloc({required this.lectureAccessor, required this.bookmarkAccessor})
    : super(const LectureLoadingState());

  final Accessor<Lecture, ()> lectureAccessor;
  final Accessor<bool, ()> bookmarkAccessor;

  late final Watched<Lecture> lectureSource = watch(lectureAccessor);
  late final Watched<bool> bookmarkSource = watch(bookmarkAccessor);

  @override
  List<Watched<Object?>> get sources => [lectureSource, bookmarkSource];

  @override
  FutureOr<MatchResult> matchSources(Emit<LectureState> emit) {
    switch ((lectureSource.state, bookmarkSource.state)) {
      case (
        DataLoaded(data: final lecture),
        DataLoaded(data: final isBookmarked),
      ):
        emit(LectureLoadedState(lecture: lecture, isBookmarked: isBookmarked));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<LectureState> emit) {
    emit(const LectureLoadingState());
  }

  @override
  void onAnyError(
    Object error,
    StackTrace? stackTrace,
    Emit<LectureState> emit,
  ) {
    emit(LectureErrorState(error.toString()));
  }

  @override
  void handlers() {
    on<ToggleBookmarkEvent>((event, emit) async {
      emitEffect(const ShowToastEffect('Bookmark toggled!'));
    });
    on<RefreshLectureEvent>((event, emit) async {
      await lectureAccessor.refresh(const ());
      await bookmarkAccessor.refresh(const ());
    });
  }
}

// ---------------------------------------------------------------------------
// 5. Tubit Implementation (Cubit + Trooper Sources)
// ---------------------------------------------------------------------------

class LectureTubit extends Tubit<LectureState> {
  LectureTubit({required this.lectureAccessor, required this.bookmarkAccessor})
    : super(const LectureLoadingState());

  final Accessor<Lecture, ()> lectureAccessor;
  final Accessor<bool, ()> bookmarkAccessor;

  late final Watched<Lecture> lecture = watch(lectureAccessor);
  late final Watched<bool> bookmark = watch(bookmarkAccessor);

  @override
  List<Watched<Object?>> get sources => [lecture, bookmark];

  @override
  MatchResult matchSources(Emit<LectureState> emit) {
    switch ((lecture.state, bookmark.state)) {
      case (DataLoaded(data: final l), DataLoaded(data: final b)):
        emit(LectureLoadedState(lecture: l, isBookmarked: b));
        return .handled;
      default:
        return .unhandled;
    }
  }

  @override
  void onAnyLoading(Emit<LectureState> emit) =>
      emit(const LectureLoadingState());

  @override
  void onAnyError(Object error, StackTrace? st, Emit<LectureState> emit) =>
      emit(LectureErrorState(error.toString()));

  Future<void> reload() async {
    await lectureAccessor.refresh(const ());
    await bookmarkAccessor.refresh(const ());
  }
}

// ---------------------------------------------------------------------------
// 6. UI Example with TlocEffectListener & BlocBuilder
// ---------------------------------------------------------------------------

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Trooper BLoC Example'))),
    ),
  );
}

class LectureView extends StatelessWidget {
  const LectureView({super.key});

  @override
  Widget build(BuildContext context) {
    return TlocEffectListener<LectureTloc, LectureEffect>(
      onEffect: (context, effect) => switch (effect) {
        ShowToastEffect(:final message) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message))),
      },
      child: BlocBuilder<LectureTloc, LectureState>(
        builder: (context, state) => switch (state) {
          LectureLoadingState() => const Center(
            child: CircularProgressIndicator(),
          ),
          LectureErrorState(:final message) => Center(
            child: Text('Error: $message'),
          ),
          LectureLoadedState(:final lecture, :final isBookmarked) => ListTile(
            title: Text(lecture.title),
            trailing: IconButton(
              icon: Icon(isBookmarked ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () =>
                  context.read<LectureTloc>().add(const ToggleBookmarkEvent()),
            ),
          ),
        },
      ),
    );
  }
}
