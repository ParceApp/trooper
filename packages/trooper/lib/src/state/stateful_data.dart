import 'package:meta/meta.dart';
import 'package:trooper/src/state/data_metadata.dart';

/// Sealed hierarchy modeling all possible states of an asynchronous data query or stream.
///
/// Designed specifically for idiomatic Dart 3.5+ pattern matching:
/// ```dart
/// final widget = switch (state) {
///   DataInitial() => const SizedBox.shrink(),
///   DataLoading() => const CircularProgressIndicator(),
///   DataLoaded(:final data) => LectureList(
///     lectures: data,
///     isRefreshing: state is DataRefreshing,
///   ),
///   DataError(:final error) => ErrorView(error),
/// };
/// ```
///
/// ### Stale-While-Revalidate (SWR) Guarantee
/// [DataRefreshing] extends [DataLoaded]. Because of this inheritance, any pattern
/// matching on `case DataLoaded(:final data)` or checking `state.hasData` continues
/// to match and evaluate to `true` while a background refresh is in-flight.
/// This prevents UI layout jumps and screen flickers.
@immutable
sealed class StatefulData<T> {
  /// Const constructor for subclasses.
  const StatefulData();

  /// Factory for a [DataInitial] state.
  factory StatefulData.initial() => DataInitial<T>();

  /// Factory for a [DataLoading] state with optional fractional [progress].
  factory StatefulData.loading({double? progress}) =>
      DataLoading<T>(progress: progress);

  /// Factory for a [DataLoaded] state with the given [data] and optional [metadata].
  factory StatefulData.loaded(T data, {DataMetadata? metadata}) =>
      DataLoaded<T>(data, metadata: metadata);

  /// Factory for a [DataRefreshing] state with the given [data], optional [progress], and optional [metadata].
  /// Represents a background refresh operation (Stale-While-Revalidate).
  factory StatefulData.refreshing(
    T data, {
    double? progress,
    DataMetadata? metadata,
  }) => DataRefreshing<T>(data, progress: progress, metadata: metadata);

  /// Factory for a [DataError] state with the given [error], optional [stackTrace], and optional [staleData].
  factory StatefulData.error(
    Object error, {
    StackTrace? stackTrace,
    T? staleData,
  }) => DataError<T>(error, stackTrace: stackTrace, staleData: staleData);

  /// Returns the current data payload if available, or `null` otherwise.
  ///
  /// This returns valid data for both [DataLoaded] and [DataRefreshing].
  T? get dataOrNull => switch (this) {
    DataLoaded<T>(:final data) => data,
    _ => null,
  };

  /// Returns the associated [DataMetadata] if available, or `null` otherwise.
  DataMetadata? get metadataOrNull => switch (this) {
    DataLoaded<T>(:final metadata) => metadata,
    _ => null,
  };

  /// Returns the error object if this is a [DataError], or `null` otherwise.
  Object? get errorOrNull => switch (this) {
    DataError<T>(error: final err) => err,
    _ => null,
  };

  /// Returns `true` if this is the initial idle state ([DataInitial]).
  bool get isInitial => this is DataInitial<T>;

  /// Returns `true` if an operation is actively in-flight.
  ///
  /// This evaluates to `true` for both initial loading ([DataLoading]) and
  /// background refreshing ([DataRefreshing]).
  bool get isLoading => this is DataLoading<T> || this is DataRefreshing<T>;

  /// Returns `true` if valid data is available for presentation ([DataLoaded] or [DataRefreshing]).
  bool get isLoaded => this is DataLoaded<T>;

  /// Returns `true` if this state represents an error ([DataError]).
  bool get isError => this is DataError<T>;

  /// Returns `true` if this state is currently performing a background refresh ([DataRefreshing]).
  bool get isRefreshing => this is DataRefreshing<T>;

  /// Executes a callback depending on the concrete runtime type of this state.
  ///
  /// If [refreshing] is omitted, [DataRefreshing] states fall back to executing [loaded].
  R when<R>({
    required R Function() initial,
    required R Function(double? progress) loading,
    required R Function(T data, DataMetadata? metadata) loaded,
    required R Function(Object error, StackTrace? stackTrace, T? staleData)
    error,
    R Function(T data, double? progress, DataMetadata? metadata)? refreshing,
  }) => switch (this) {
    DataInitial<T>() => initial(),
    DataLoading<T>(:final progress) => loading(progress),
    DataRefreshing<T>(:final data, :final progress, :final metadata) =>
      refreshing != null
          ? refreshing(data, progress, metadata)
          : loaded(data, metadata),
    DataLoaded<T>(:final data, :final metadata) => loaded(data, metadata),
    DataError<T>(error: final err, :final stackTrace, :final staleData) =>
      error(err, stackTrace, staleData),
  };

  /// Executes a callback matching this state, or returns the result of [orElse].
  R maybeWhen<R>({
    required R Function() orElse,
    R Function()? initial,
    R Function(double? progress)? loading,
    R Function(T data, DataMetadata? metadata)? loaded,
    R Function(T data, double? progress, DataMetadata? metadata)? refreshing,
    R Function(Object error, StackTrace? stackTrace, T? staleData)? error,
  }) => switch (this) {
    DataInitial<T>() => initial != null ? initial() : orElse(),
    DataLoading<T>(:final progress) =>
      loading != null ? loading(progress) : orElse(),
    DataRefreshing<T>(:final data, :final progress, :final metadata) =>
      refreshing != null
          ? refreshing(data, progress, metadata)
          : (loaded != null ? loaded(data, metadata) : orElse()),
    DataLoaded<T>(:final data, :final metadata) =>
      loaded != null ? loaded(data, metadata) : orElse(),
    DataError<T>(error: final err, :final stackTrace, :final staleData) =>
      error != null ? error(err, stackTrace, staleData) : orElse(),
  };

  /// Maps this state to a value of type [R] using type-safe callbacks.
  R map<R>({
    required R Function(DataInitial<T> state) initial,
    required R Function(DataLoading<T> state) loading,
    required R Function(DataLoaded<T> state) loaded,
    required R Function(DataRefreshing<T> state) refreshing,
    required R Function(DataError<T> state) error,
  }) => switch (this) {
    final DataInitial<T> s => initial(s),
    final DataRefreshing<T> s => refreshing(s),
    final DataLoaded<T> s => loaded(s),
    final DataLoading<T> s => loading(s),
    final DataError<T> s => error(s),
  };
}

/// The initial idle state before any data query has been triggered.
final class DataInitial<T> extends StatefulData<T> {
  /// Creates a [DataInitial] state.
  const DataInitial();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DataInitial<T>;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'DataInitial<$T>()';
}

/// Represents an active initial loading operation where no cached data is available yet.
final class DataLoading<T> extends StatefulData<T> {
  /// Creates a [DataLoading] state with optional fractional [progress] (between 0.0 and 1.0).
  const DataLoading({this.progress});

  /// Optional fractional progress indicator between `0.0` and `1.0`.
  final double? progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataLoading<T> && other.progress == progress;

  @override
  int get hashCode => Object.hash(runtimeType, progress);

  @override
  String toString() => 'DataLoading<$T>(progress: $progress)';
}

/// Represents successfully loaded data ready for presentation.
base class DataLoaded<T> extends StatefulData<T> {
  /// Creates a [DataLoaded] state with the given [data] and optional [metadata].
  const DataLoaded(this.data, {this.metadata});

  /// The strongly-typed data payload.
  final T data;

  /// Optional metadata regarding origin and caching timestamps.
  final DataMetadata? metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataLoaded<T> &&
          other.runtimeType == runtimeType &&
          other.data == data &&
          other.metadata == metadata;

  @override
  int get hashCode => Object.hash(runtimeType, data, metadata);

  @override
  String toString() => 'DataLoaded<$T>(data: $data, metadata: $metadata)';
}

/// Represents a background refresh operation (Stale-While-Revalidate).
///
/// **Crucial Architecture Detail:**
/// [DataRefreshing] extends [DataLoaded]. Because of this, previous data remains
/// completely accessible via [data] and [dataOrNull]. The UI continues rendering
/// the previous data uninterruptedly without showing a disruptive full-screen spinner.
final class DataRefreshing<T> extends DataLoaded<T> {
  /// Creates a [DataRefreshing] state wrapping existing [data] during a background revalidation.
  const DataRefreshing(super.data, {this.progress, super.metadata});

  /// Optional fractional progress of the background refresh (between 0.0 and 1.0).
  final double? progress;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataRefreshing<T> &&
          other.data == data &&
          other.progress == progress &&
          other.metadata == metadata;

  @override
  int get hashCode => Object.hash(runtimeType, data, progress, metadata);

  @override
  String toString() =>
      'DataRefreshing<$T>(data: $data, progress: $progress, metadata: $metadata)';
}

/// Represents an error state encountered during fetching or stream consumption.
final class DataError<T> extends StatefulData<T> {
  /// Creates a [DataError] state.
  const DataError(this.error, {this.stackTrace, this.staleData});

  /// The error or exception object that occurred.
  final Object error;

  /// The stack trace associated with [error], if available.
  final StackTrace? stackTrace;

  /// Previously cached data that was retained when the refresh attempt failed, if any.
  final T? staleData;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataError<T> &&
          other.error == error &&
          other.staleData == staleData;

  @override
  int get hashCode => Object.hash(runtimeType, error, staleData);

  @override
  String toString() => 'DataError<$T>(error: $error, staleData: $staleData)';
}
