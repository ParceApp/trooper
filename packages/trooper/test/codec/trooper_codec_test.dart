import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperCodec', () {
    test('string codec passes through unchanged', () {
      const codec = TrooperCodec.string;
      expect(codec.encode('hello'), 'hello');
      expect(codec.decode('hello'), 'hello');
    });

    test('integer codec encodes and decodes ints', () {
      const codec = TrooperCodec.integer;
      expect(codec.encode(42), '42');
      expect(codec.decode('42'), 42);
      expect(() => codec.decode('abc'), throwsFormatException);
    });

    test('doublePrecision codec encodes and decodes doubles', () {
      const codec = TrooperCodec.doublePrecision;
      expect(codec.encode(3.1415), '3.1415');
      expect(codec.decode('3.1415'), closeTo(3.1415, 0.0001));
      expect(() => codec.decode('invalid'), throwsFormatException);
    });

    test('boolean codec encodes and decodes booleans', () {
      const codec = TrooperCodec.boolean;
      expect(codec.encode(true), 'true');
      expect(codec.encode(false), 'false');
      expect(codec.decode('true'), isTrue);
      expect(codec.decode('false'), isFalse);
      expect(codec.decode('anything_else'), isFalse);
    });

    test('dateTime codec encodes to ISO-8601 and parses back', () {
      const codec = TrooperCodec.dateTime;
      final now = DateTime.utc(2026, 10, 8, 15, 30);
      final encoded = codec.encode(now);
      expect(encoded, now.toIso8601String());
      expect(codec.decode(encoded), now);
    });

    test('json codec serializes and deserializes objects', () {
      final codec = TrooperCodec.json<_User>(
        fromJson: (json) => _User(
          id: (json as Map<String, dynamic>)['id'] as int,
          name: json['name'] as String,
        ),
        toJson: (u) => {'id': u.id, 'name': u.name},
      );

      const user = _User(id: 7, name: 'Alice');
      final encoded = codec.encode(user);
      final decoded = codec.decode(encoded);

      expect(decoded.id, 7);
      expect(decoded.name, 'Alice');
    });

    test('list codec encodes and decodes lists of primitives', () {
      final codec = TrooperCodec.list(TrooperCodec.integer);
      final list = [1, 2, 3, 42];
      final encoded = codec.encode(list);
      final decoded = codec.decode(encoded);

      expect(decoded, [1, 2, 3, 42]);
      expect(codec.decode('[]'), isEmpty);
    });

    test('map codec encodes and decodes key-value pairs', () {
      final codec = TrooperCodec.map(
        keyCodec: TrooperCodec.string,
        valueCodec: TrooperCodec.integer,
      );

      final map = {'a': 1, 'b': 2};
      final encoded = codec.encode(map);
      final decoded = codec.decode(encoded);

      expect(decoded, {'a': 1, 'b': 2});
      expect(codec.decode('{}'), isEmpty);
    });

    test('custom codec transforms using arbitrary functions', () {
      final codec = TrooperCodec.custom<int>(
        to: (val) => '0x${val.toRadixString(16)}',
        from: (str) => int.parse(str.replaceFirst('0x', ''), radix: 16),
      );

      expect(codec.encode(255), '0xff');
      expect(codec.decode('0xff'), 255);
    });
  });
}

class _User {
  const _User({required this.id, required this.name});
  final int id;
  final String name;
}
