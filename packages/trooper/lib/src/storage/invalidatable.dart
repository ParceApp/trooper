/// An interface for components that manage cached or derived resources
/// and can be invalidated.
///
/// Implemented by cache stores, query accessors, controllers, and mutation triggers
/// to provide a uniform API for marking cached data as stale or purging it.
///
/// ### Example:
/// ```dart
/// class MyCache implements Invalidatable {
///   @override
///   void invalidate() {
///     // Mark all entries as stale
///   }
/// }
/// ```
abstract interface class Invalidatable {
  /// Invalidates cached data, marking it as stale or purging it.
  void invalidate();
}
