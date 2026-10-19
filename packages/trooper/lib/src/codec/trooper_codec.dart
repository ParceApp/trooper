import 'dart:convert';

import 'package:trooper/src/error/trooper_exception.dart';

/// A specialized [Codec] for serializing and deserializing domain data of type [T]
/// to and from [String] representations for persistent storage or caching.
///
/// Extends Dart's standard [Codec] from `dart:convert`, enabling seamless composition
/// and full compatibility with the Dart SDK converter ecosystem.
///
/// The encoded string is persisted as is (plain text) by the configured
/// `StorageBackend`. Do not rely on a codec for confidentiality; encrypt in the
/// backend instead (see `StorageBackend`).
///
/// ### Pre-built Presets:
/// ```dart
/// TrooperCodec.string;           // String <-> String
/// TrooperCodec.integer;          // int <-> String
/// TrooperCodec.doublePrecision;  // double <-> String
/// TrooperCodec.boolean;          // bool <-> String
/// TrooperCodec.dateTime;         // DateTime <-> ISO-8601 String
///
/// // Complex models:
/// final userCodec = TrooperCodec.json<User>(
///   fromJson: User.fromJson,
///   toJson: (u) => u.toJson(),
/// );
///
/// // Collections:
/// final idListCodec = TrooperCodec.list(TrooperCodec.integer);
/// final dictCodec = TrooperCodec.map(
///   keyCodec: TrooperCodec.string,
///   valueCodec: TrooperCodec.integer,
/// );
///
/// // Custom codecs:
/// final customCodec = TrooperCodec.custom<Color>(
///   to: (c) => c.value.toRadixString(16),
///   from: (s) => Color(int.parse(s, radix: 16)),
/// );
/// ```
///
/// [encode] and [decode] report every failure as a [TrooperCodecException]
/// that carries the original error.
abstract final class TrooperCodec<T> extends Codec<T, String> {
  /// Private const constructor.
  const TrooperCodec._();

  /// Encodes [input] to a string.
  ///
  /// Throws a [TrooperCodecException] if encoding fails.
  @override
  String encode(T input) {
    try {
      return encoder.convert(input);
    } on TrooperCodecException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        TrooperCodecException(
          'Failed to encode a value of type ${input.runtimeType}.',
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  /// Decodes [encoded] to a value of type [T].
  ///
  /// Throws a [TrooperCodecException] if decoding fails.
  @override
  T decode(String encoded) {
    try {
      return decoder.convert(encoded);
    } on TrooperCodecException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        TrooperCodecException(
          'Failed to decode a value of type $T.',
          error: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  /// Creates a custom [TrooperCodec] from inline [to] and [from] converter functions.
  static TrooperCodec<T> custom<T>({
    required String Function(T input) to,
    required T Function(String input) from,
  }) => _FunctionalCodec<T>(to: to, from: from);

  /// Pass-through codec for [String] values.
  static const TrooperCodec<String> string = _StringCodec();

  /// Codec serializing [int] values to and from decimal strings.
  static const TrooperCodec<int> integer = _IntCodec();

  /// Codec serializing [double] values to and from floating-point strings.
  static const TrooperCodec<double> doublePrecision = _DoubleCodec();

  /// Codec serializing [bool] values to and from `'true'` and `'false'`.
  static const TrooperCodec<bool> boolean = _BoolCodec();

  /// Codec serializing [DateTime] values to and from ISO-8601 strings.
  static const TrooperCodec<DateTime> dateTime = _DateTimeCodec();

  /// Creates a JSON-based [TrooperCodec] utilizing [fromJson] and [toJson] transformers.
  static TrooperCodec<T> json<T>({
    required T Function(dynamic json) fromJson,
    required Object? Function(T value) toJson,
  }) => _JsonCodec<T>(fromJson: fromJson, toJson: toJson);

  /// Creates a [TrooperCodec] for a [List] of elements using an [itemCodec].
  static TrooperCodec<List<T>> list<T>(Codec<T, String> itemCodec) =>
      _ListCodec<T>(itemCodec);

  /// Creates a [TrooperCodec] for a [Map] using a [keyCodec] and [valueCodec].
  static TrooperCodec<Map<K, V>> map<K, V>({
    required Codec<K, String> keyCodec,
    required Codec<V, String> valueCodec,
  }) => _MapCodec<K, V>(keyCodec: keyCodec, valueCodec: valueCodec);
}

final class _FunctionalConverter<S, T> extends Converter<S, T> {
  const _FunctionalConverter(this._convert);
  final T Function(S input) _convert;

  @override
  T convert(S input) => _convert(input);
}

final class _FunctionalCodec<T> extends TrooperCodec<T> {
  const _FunctionalCodec({required this.to, required this.from}) : super._();
  final String Function(T input) to;
  final T Function(String input) from;

  @override
  Converter<T, String> get encoder => _FunctionalConverter(to);

  @override
  Converter<String, T> get decoder => _FunctionalConverter(from);
}

final class _StringCodec extends TrooperCodec<String> {
  const _StringCodec() : super._();

  @override
  Converter<String, String> get encoder =>
      const _FunctionalConverter(_identity);

  @override
  Converter<String, String> get decoder =>
      const _FunctionalConverter(_identity);

  static String _identity(String s) => s;
}

final class _IntCodec extends TrooperCodec<int> {
  const _IntCodec() : super._();

  @override
  Converter<int, String> get encoder =>
      const _FunctionalConverter(_intToString);

  @override
  Converter<String, int> get decoder => const _FunctionalConverter(int.parse);

  static String _intToString(int n) => n.toString();
}

final class _DoubleCodec extends TrooperCodec<double> {
  const _DoubleCodec() : super._();

  @override
  Converter<double, String> get encoder =>
      const _FunctionalConverter(_doubleToString);

  @override
  Converter<String, double> get decoder =>
      const _FunctionalConverter(double.parse);

  static String _doubleToString(double d) => d.toString();
}

final class _BoolCodec extends TrooperCodec<bool> {
  const _BoolCodec() : super._();

  @override
  Converter<bool, String> get encoder =>
      const _FunctionalConverter(_boolToString);

  @override
  Converter<String, bool> get decoder =>
      const _FunctionalConverter(_stringToBool);

  static String _boolToString(bool b) => b ? 'true' : 'false';
  static bool _stringToBool(String s) => s == 'true';
}

final class _DateTimeCodec extends TrooperCodec<DateTime> {
  const _DateTimeCodec() : super._();

  @override
  Converter<DateTime, String> get encoder =>
      const _FunctionalConverter(_dtToString);

  @override
  Converter<String, DateTime> get decoder =>
      const _FunctionalConverter(DateTime.parse);

  static String _dtToString(DateTime dt) => dt.toIso8601String();
}

final class _JsonCodec<T> extends TrooperCodec<T> {
  const _JsonCodec({required this.fromJson, required this.toJson}) : super._();
  final T Function(dynamic json) fromJson;
  final Object? Function(T value) toJson;

  @override
  Converter<T, String> get encoder =>
      _FunctionalConverter((v) => jsonEncode(toJson(v)));

  @override
  Converter<String, T> get decoder =>
      _FunctionalConverter((s) => fromJson(jsonDecode(s)));
}

final class _ListCodec<T> extends TrooperCodec<List<T>> {
  const _ListCodec(this.itemCodec) : super._();
  final Codec<T, String> itemCodec;

  @override
  Converter<List<T>, String> get encoder => _FunctionalConverter(
    (list) => jsonEncode(list.map(itemCodec.encode).toList()),
  );

  @override
  Converter<String, List<T>> get decoder => _FunctionalConverter(
    (str) => (jsonDecode(str) as List<dynamic>)
        .map((e) => itemCodec.decode(e as String))
        .toList(),
  );
}

final class _MapCodec<K, V> extends TrooperCodec<Map<K, V>> {
  const _MapCodec({required this.keyCodec, required this.valueCodec})
    : super._();
  final Codec<K, String> keyCodec;
  final Codec<V, String> valueCodec;

  @override
  Converter<Map<K, V>, String> get encoder => _FunctionalConverter((map) {
    final encoded = <String, String>{};
    for (final entry in map.entries) {
      encoded[keyCodec.encode(entry.key)] = valueCodec.encode(entry.value);
    }
    return jsonEncode(encoded);
  });

  @override
  Converter<String, Map<K, V>> get decoder => _FunctionalConverter((str) {
    final decoded = jsonDecode(str) as Map<String, dynamic>;
    final result = <K, V>{};
    for (final entry in decoded.entries) {
      result[keyCodec.decode(entry.key)] = valueCodec.decode(
        entry.value as String,
      );
    }
    return result;
  });
}
