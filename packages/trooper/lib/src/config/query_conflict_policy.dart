import 'package:trooper/src/error/trooper_exception.dart';

/// Defines how in-flight conflicts for the same query slot are resolved.
///
/// A conflict occurs when a query request is triggered while a prior request for the
/// same query slot (identified by query name and entity key) is still in-flight, AND:
/// - Parameters differ (`paramA != paramB`), OR
/// - `forceRefresh: true` was explicitly requested, OR
/// - Deduplication is disabled (`deduplicate: false`).
///
/// When parameters match and `forceRefresh` is false, requests are deduplicated by default
/// without triggering a conflict.
///
/// ### Overview of Conflict Policies
///
/// | Policy | Network Action | Prior Caller Future | Stream & Cache | Primary Use Case |
/// |---|---|---|---|---|
/// | [cancel] | Aborted via token | Throws [TrooperCancelledException] | Receives latest data | Strict cancellation, search fields |
/// | [forward] | Aborted via token | Awaits and receives new data | Receives latest data | Reactive UI, filter changes, pagination |
/// | [parallel] | Continues running | Receives its own data | Protected by sequence-ID | Independent file exports, batch computations |
///
/// ### Example Configuration
/// ```dart
/// // In TrooperConfig:
/// const config = TrooperConfig(
///   conflictPolicy: QueryConflictPolicy.forward,
///   deduplicate: true,
/// );
/// ```
enum QueryConflictPolicy {
  /// Aborts the ongoing in-flight request and signals cancellation to the prior caller.
  ///
  /// ### Behavior:
  /// - **Network**: The prior request's `TrooperCancelToken` is cancelled immediately,
  ///   saving server processing and bandwidth.
  /// - **Prior Caller**: The [Future] of the prior caller completes with a [TrooperCancelledException].
  /// - **New Request**: Executes fresh and emits its result to the cache and reactive stream.
  ///
  /// ### Use Cases:
  /// - Search autocompletion (typeahead) where obsolete queries must be aborted and callers
  ///   explicitly want to catch cancellation.
  /// - User navigation where leaving a view strictly invalidates ongoing tasks.
  ///
  /// ```dart
  /// // First query cancelled; second query completes normally:
  /// try {
  ///   final f1 = query.get((search: 'flutt'));
  ///   final f2 = query.get((search: 'flutter'));
  ///   await f1; // Throws TrooperCancelledException!
  /// } on TrooperCancelledException {
  ///   // Handle cancelled search
  /// }
  /// ```
  cancel,

  /// Aborts the previous network request, but seamlessly forwards awaiting callers to the new request.
  ///
  /// This is the recommended default for reactive user interfaces.
  ///
  /// ### Behavior:
  /// - **Network**: The prior request's `TrooperCancelToken` is cancelled immediately,
  ///   preventing redundant data transfer.
  /// - **Prior Caller**: The [Future] of the prior caller is chained to the new request.
  ///   It does NOT throw a [TrooperCancelledException]; instead, it awaits and resolves
  ///   with the new request's result without error. This holds even if the superseded
  ///   fetch ignores its token and resolves first, throws because it honors the token,
  ///   or was waiting for a retry: its own outcome is discarded and never reaches the
  ///   stream or cache. If the new request fails, the prior caller receives that error.
  /// - **New Request**: Executes and fulfills all awaiting callers in the chain simultaneously.
  ///
  /// ### Use Cases:
  /// - Filter tabs, pagination, and dropdown selections where rapid user interactions
  ///   should smoothly update without requiring `try/catch(TrooperCancelledException)`
  ///   blocks in the UI layer.
  /// - Multiple screens or widgets sharing the same query slot across state transitions.
  ///
  /// ```dart
  /// // Screen 1 requests filter A; Screen 2 quickly switches to filter B:
  /// final f1 = query.get((filter: 'active'));
  /// final f2 = query.get((filter: 'archived'));
  ///
  /// // Both callers seamlessly resolve with the 'archived' data:
  /// final r1 = await f1; // 'archived' result
  /// final r2 = await f2; // 'archived' result
  /// ```
  forward,

  /// Allows multiple requests to run concurrently in parallel without cancelling earlier ones.
  ///
  /// ### Behavior:
  /// - **Network**: All requests execute concurrently until completion. No `TrooperCancelToken`
  ///   is cancelled.
  /// - **Individual Callers**: Every caller awaiting `get()` receives its own specific result.
  /// - **Stream and Cache Protection**: A sequence-ID guard ensures that only chronologically
  ///   newer requests update the reactive stream and cache. If an older request completes
  ///   after a newer one (out-of-order arrival), its result is returned to its direct caller
  ///   but discarded by the stream, preventing state corruption.
  ///
  /// ### Use Cases:
  /// - Independent background jobs or export tasks (e.g. exporting PDF and CSV simultaneously).
  /// - Fire-and-forget computations where every caller must receive its specific output.
  ///
  /// ```dart
  /// // Two parallel export jobs run simultaneously:
  /// final pdfFuture = exportQuery.get((format: 'pdf'));
  /// final csvFuture = exportQuery.get((format: 'csv'));
  ///
  /// final (pdf, csv) = await (pdfFuture, csvFuture).wait;
  /// ```
  parallel,
}

/// Shorthand alias for [QueryConflictPolicy].
typedef ConflictPolicy = QueryConflictPolicy;
