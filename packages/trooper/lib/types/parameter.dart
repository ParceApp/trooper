/// Type alias representing parameters passed to queries, streams, and mutations.
///
/// In Trooper, all query and mutation parameters are strongly-typed Dart 3 records,
/// such as `()`, `(int id,)`, or `({String filter, int page})`.
typedef Parameter = Record;
