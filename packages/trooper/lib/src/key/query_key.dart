/// An immutable, zero-cost identifier representing a query or resource.
///
/// Wraps a Dart 3 record `(String name, Object? key)` as an
/// extension type, leveraging built-in compile-time record value equality
/// and hash code generation.
///
/// ### Example:
/// ```dart
/// // Unkeyed query:
/// const key1 = QueryKey('user_profile');
///
/// // Keyed query for specific entity:
/// const key2 = QueryKey.keyed('lecture', key: 42);
///
/// // Native value equality:
/// assert(key2 == QueryKey.keyed('lecture', key: 42));
/// ```
extension type const QueryKey._((String name, Object? key) _value) {
  /// Creates an unkeyed [QueryKey] with a [name].
  const QueryKey(String name) : _value = (name, null);

  /// Creates a keyed [QueryKey] identifying an entity [key] within a [name] collection.
  const QueryKey.keyed(String name, {required Object key})
    : _value = (name, key);

  /// The namespace name of the query (e.g. `'lectures'`, `'user_profile'`).
  String get name => _value.$1;

  /// The entity identifier within the namespace, or `null` for unkeyed single queries (e.g. the `id` of an user).
  Object? get key => _value.$2;

  /// Whether this query targets a specific entity key.
  bool get isKeyed => key != null;

  /// Checks whether this key belongs to the specified query [name].
  bool matchesName(String name) => this.name == name;

  /// Checks whether this key matches both [name] and entity [entityKey].
  bool matchesKey(String name, Object? entityKey) =>
      this.name == name && key == entityKey;

  /// Generates a deterministic key suitable for persistence backends
  /// (Filesystem, SharedPreferences, SQLite, Redis).
  String get storageKey => key != null ? '$name:$key' : name;

  /// Formatted representation of this query key for logging and diagnostics.
  String describe() {
    final buffer = StringBuffer('QueryKey($name');
    if (key != null) buffer.write(', key: $key');
    buffer.write(')');
    return buffer.toString();
  }
}
