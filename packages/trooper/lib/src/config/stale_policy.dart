/// Defines how cached data is treated while a background revalidation is in-flight.
enum StalePolicy {
  /// Keep and emit stale data immediately while a background fetch runs.
  ///
  /// Emits [DataRefreshing] preserving cached data to prevent UI flicker.
  /// This is the default Stale-While-Revalidate (SWR) behavior.
  keepStaleWhileRevalidate,

  /// Discard stale data and emit a hard [DataLoading] state before fetching.
  discardStaleOnRefresh,
}
