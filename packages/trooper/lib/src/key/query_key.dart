import 'package:trooper/types/parameter.dart';

/// An immutable, zero-cost identifier representing a query or resource.
///
/// Wraps a Dart 3 record `(String name, Object? key)` as an
/// extension type, leveraging built-in compile-time record value equality
/// and hash code generation.
///
/// ### Example:
/// ```dart
/// // Unkeyed query:
/// const key1 = QueryKey('user_profile', ());
///
/// // Keyed query for specific entity:
/// const key2 = QueryKey.keyed('lecture', parameter: (), key: 42);
///
/// // Native value equality:
/// assert(key2 == QueryKey.keyed('lecture', parameter: (), key: 42));
/// ```
extension type const QueryKey._(
  (String name, Parameter parameter, Object? key) _value
) {
  /// Creates an unkeyed [QueryKey] with a [name].
  const QueryKey(String name, Parameter parameter)
    : _value = (name, parameter, null);

  /// Creates a keyed [QueryKey] identifying an entity [key] within a [name] collection.
  const QueryKey.keyed(
    String name, {
    required Parameter parameter,
    required Object key,
  }) : _value = (name, parameter, key);

  /// The namespace name of the query (e.g. `'tasks'`, `'user_profile'`).
  String get name => _value.$1;

  /// The parameters associated with the query, or an empty record for queries without a parameter (e.g. the `filter` of a list).
  Parameter get parameter => _value.$2;

  /// The entity identifier within the namespace, or `null` for unkeyed single queries (e.g. the `id` of an user).
  Object? get key => _value.$3;

  /// Whether this query targets a specific entity key.
  bool get isKeyed => key != null;

  /// Whether this query has a non-empty parameter.
  bool get hasParameter => parameter != const ();

  /// Checks whether this key belongs to the specified query [name].
  bool matchesName(String name) => this.name == name;

  /// Checks whether this key matches [parameter].
  bool matchesParameter(Parameter parameter) => this.parameter == parameter;

  /// Checks whether this key belongs to the specified entity [entityKey].
  bool matchesKey(Object? entityKey) => key == entityKey;

  /// Checks whether this key matches the specified [name], [parameter], and [entityKey].
  bool matches({
    required String name,
    required Parameter parameter,
    required Object? entityKey,
  }) =>
      matchesName(name) && matchesParameter(parameter) && matchesKey(entityKey);

  /// Checks whether this key matches the specified [name] and [entityKey].
  bool matchesNameAndKey({required String name, required Object? entityKey}) =>
      matchesName(name) && matchesKey(entityKey);

  /// Generates a deterministic identifier that is a combination of name and key, suitable for queueing, logging and diagnostics.
  String get identifier {
    final buffer = StringBuffer(name);
    if (isKeyed) buffer.write(':$key');
    return buffer.toString();
  }

  /// Version of the [storageKey] layout. Keys written by an older layout are
  /// never read again.
  static const int storageKeyVersion = 1;

  /// Prefix shared by the [storageKey] of every query in [namespace].
  ///
  /// Used to find all persisted entries of a namespace, including those
  /// written in earlier sessions.
  static String storagePrefix(String namespace) =>
      'trooper:$storageKeyVersion:${Uri.encodeComponent(namespace)}:';

  /// Generates a deterministic key suitable for persistence backends
  /// (Filesystem, SharedPreferences, SQLite, Redis).
  ///
  /// Layout: `trooper:<version>:<name>:<parameter>[:<key>]`, each segment
  /// URI-encoded. Parameter and key are taken from their `toString()`, which
  /// must therefore be stable across sessions and distinct for unequal
  /// values. See [hasStableStorageKey].
  String get storageKey {
    final buffer = StringBuffer(storagePrefix(name))
      ..write(Uri.encodeComponent('$parameter'));
    if (isKeyed) buffer.write(':${Uri.encodeComponent('$key')}');
    return buffer.toString();
  }

  /// Whether [storageKey] can identify this query across sessions.
  ///
  /// `false` if the parameter or key falls back to the default
  /// `Object.toString()` (`Instance of '…'`) or is a closure: unequal values
  /// would then share one [storageKey]. Troopers skip L2 storage for such
  /// keys; give the parameter class a stable `toString()` to persist it.
  bool get hasStableStorageKey =>
      _isStable('$parameter') && (!isKeyed || _isStable('$key'));

  static bool _isStable(String text) =>
      !text.contains("Instance of '") && !text.contains('Closure: ');

  /// Formatted representation of this query key for logging and diagnostics.
  String describe() {
    final buffer = StringBuffer('QueryKey($name');
    if (parameter != const ()) buffer.write(', parameter: $parameter');
    if (key != null) buffer.write(', key: $key');
    buffer.write(')');
    return buffer.toString();
  }
}
