import 'dart:convert';

import 'package:trooper/src/key/query_key.dart';

/// An envelope wrapping persisted cache payloads with lifecycle and expiration metadata.
///
/// Stored in [StorageBackend] to allow deterministic staleness detection,
/// instant hydration on app start, and Stale-While-Revalidate (SWR) background refreshes.
///
/// ### Stable format
/// Version [currentVersion] is a JSON object with the fields `version`, `payload`
/// (the codec output), `createdAt` and the optional `expiresAt` and
/// `timeToLiveMillis` (ISO 8601 timestamps, milliseconds). Any change to these
/// fields increments [currentVersion].
///
/// Troopers read entries via [tryDecode], which rejects entries without a version
/// or with a version other than [currentVersion] (for example written by a newer
/// app release). Such entries are deleted and the data is fetched again; there is
/// no migration. The envelope version is independent of the storage key layout
/// version in [QueryKey.storageKey] (`trooper:1:…`).
final class StorageEnvelope {
  /// Creates a [StorageEnvelope] with the provided [payload] and timestamps.
  const StorageEnvelope({
    required this.payload,
    required this.createdAt,
    this.expiresAt,
    this.timeToLiveMillis,
    this.version = currentVersion,
  });

  /// The current schema version of the envelope.
  static const int currentVersion = 1;

  /// Schema version for format migration.
  final int version;

  /// The serialized payload string produced by a codec.
  final String payload;

  /// The timestamp when this entry was created or fetched.
  final DateTime createdAt;

  /// The exact timestamp when this entry expires, or `null` if it has no expiration.
  final DateTime? expiresAt;

  /// The original time-to-live in milliseconds, or `null` if permanent.
  final int? timeToLiveMillis;

  /// The duration for which this entry was configured to remain fresh.
  Duration? get timeToLive => timeToLiveMillis != null
      ? Duration(milliseconds: timeToLiveMillis!)
      : null;

  /// The elapsed duration since this entry was created.
  Duration get age => DateTime.now().difference(createdAt);

  /// Whether this entry has expired according to its [expiresAt] timestamp.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether this entry is still fresh and valid.
  bool get isFresh => !isExpired;

  /// Serializes this envelope to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'version': version,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    if (timeToLiveMillis != null) 'timeToLiveMillis': timeToLiveMillis,
  };

  /// Deserializes a [StorageEnvelope] from a JSON map.
  factory StorageEnvelope.fromJson(Map<String, dynamic> json) =>
      StorageEnvelope(
        version: json['version'] as int? ?? currentVersion,
        payload: json['payload'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        timeToLiveMillis: json['timeToLiveMillis'] as int?,
      );

  /// Encodes this envelope to a JSON string.
  String encode() => jsonEncode(toJson());

  /// Decodes a [StorageEnvelope] from a raw JSON string.
  ///
  /// Does not check [version]; use [tryDecode] to read persisted entries.
  static StorageEnvelope decode(String raw) =>
      StorageEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Safely attempts to decode a [StorageEnvelope] from a raw string, returning `null` on failure.
  ///
  /// Also returns `null` if the entry has no version or a version other than
  /// [currentVersion].
  static StorageEnvelope? tryDecode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic> &&
          json['version'] == currentVersion &&
          json.containsKey('payload') &&
          json.containsKey('createdAt')) {
        return StorageEnvelope.fromJson(json);
      }
    } catch (_) {
      // Non-critical decoding failure
    }
    return null;
  }
}
