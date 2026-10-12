import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('StorageEnvelope', () {
    test('encodes to JSON and decodes back with identical metadata', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(minutes: 30));

      final original = StorageEnvelope(
        payload: '{"user":"test"}',
        createdAt: now,
        expiresAt: expires,
        timeToLiveMillis: 1800000,
        version: 1,
      );

      final encoded = original.encode();
      expect(encoded, isA<String>());

      final decoded = StorageEnvelope.decode(encoded);
      expect(decoded.payload, '{"user":"test"}');
      expect(
        decoded.createdAt.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
      expect(
        decoded.expiresAt?.millisecondsSinceEpoch,
        expires.millisecondsSinceEpoch,
      );
      expect(decoded.timeToLiveMillis, 1800000);
      expect(decoded.version, 1);
      expect(decoded.isExpired, isFalse);
    });

    test('isExpired is true when expiresAt is in the past', () {
      final now = DateTime.now();
      final expired = StorageEnvelope(
        payload: 'old',
        createdAt: now.subtract(const Duration(hours: 2)),
        expiresAt: now.subtract(const Duration(hours: 1)),
      );

      expect(expired.isExpired, isTrue);
    });

    test('isExpired is false when expiresAt is null (permanent cache)', () {
      final permanent = StorageEnvelope(
        payload: 'forever',
        createdAt: DateTime.now(),
        expiresAt: null,
      );

      expect(permanent.isExpired, isFalse);
    });

    test(
      'tryDecode safely returns null on malformed JSON or invalid schema',
      () {
        expect(StorageEnvelope.tryDecode('not a json'), isNull);
        expect(StorageEnvelope.tryDecode('{bad}'), isNull);
        expect(StorageEnvelope.tryDecode('{"some_key": 123}'), isNull);
        expect(
          StorageEnvelope.tryDecode('{"payload": "only_payload"}'),
          isNull,
        );
        expect(StorageEnvelope.tryDecode(''), isNull);
      },
    );
  });
}
