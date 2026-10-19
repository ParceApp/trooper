import 'dart:async';
import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

final failingCodec = TrooperCodec.custom<String>(
  to: (value) {
    if (value == 'THROW') {
      throw const FormatException('Cannot encode corrupted object');
    }
    return value;
  },
  from: (serialized) => serialized,
);

class ThrowingStorageBackend extends InMemoryStorageBackend {
  ThrowingStorageBackend({this.failWrite = false, this.failDelete = false});

  bool failWrite;
  bool failDelete;

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) {
      throw StateError('Disk write failure');
    }
    return super.write(key, value);
  }

  @override
  Future<String?> delete(String key) async {
    if (failDelete) {
      throw StateError('Disk delete failure');
    }
    return super.delete(key);
  }
}

void main() {
  group('TrooperTimeoutException in QueryTrooper and KeyedQueryTrooper', () {
    test(
      'QueryTrooper throws TrooperTimeoutException when query exceeds timeout',
      () async {
        final query = QueryTrooper<String, ()>(
          namespace: 'timeout_query',
          config: const TrooperConfig(timeout: Duration(milliseconds: 50)),
          fetch: (param) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return 'Delayed response';
          },
        );

        await expectLater(
          query.get(const ()),
          throwsA(
            isA<TrooperTimeoutException>().having(
              (e) => e.timeout,
              'timeout',
              const Duration(milliseconds: 50),
            ),
          ),
        );

        expect(query.stream.currentState, isA<DataError<String>>());
        final errorState = query.stream.currentState as DataError<String>;
        expect(errorState.error, isA<TrooperTimeoutException>());

        await query.dispose();
      },
    );

    test(
      'KeyedQueryTrooper throws TrooperTimeoutException when query exceeds timeout',
      () async {
        final query = KeyedQueryTrooper<String, String, ()>(
          namespace: 'keyed_timeout_query',
          config: const TrooperConfig(timeout: Duration(milliseconds: 50)),
          fetch: (key, param) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return 'Delayed for $key';
          },
        );

        await expectLater(
          query.getKey('user1', const ()),
          throwsA(isA<TrooperTimeoutException>()),
        );

        final keyState = query.stream.stateOf('user1');
        expect(keyState, isA<DataError<String>>());
        expect(
          (keyState as DataError<String>).error,
          isA<TrooperTimeoutException>(),
        );

        await query.dispose();
      },
    );
  });

  group('TrooperStorageException in LocalTrooper', () {
    test(
      'set throws TrooperCodecException when codec fails to encode value',
      () {
        final trooper = LocalTrooper<String, ()>(
          namespace: 'failing_codec_local',
          initialValue: 'init',
          codec: failingCodec,
          config: TrooperConfig(storage: InMemoryStorageBackend()),
        );

        expect(
          () => trooper.set('THROW', const ()),
          throwsA(
            isA<TrooperCodecException>().having(
              (e) => e.message,
              'message',
              contains('Failed to encode'),
            ),
          ),
        );

        trooper.dispose();
      },
    );

    test(
      'setAsync awaits storage and throws TrooperStorageException on write failure',
      () async {
        final storage = ThrowingStorageBackend(failWrite: true);
        final trooper = LocalTrooper<String, ()>(
          namespace: 'async_write_local',
          initialValue: 'init',
          codec: TrooperCodec.string,
          config: TrooperConfig(storage: storage),
        );

        await expectLater(
          trooper.setAsync('new_val', const ()),
          throwsA(
            isA<TrooperStorageException>().having(
              (e) => e.message,
              'message',
              contains('Failed to persist state'),
            ),
          ),
        );

        // Parameterless variant
        await expectLater(
          ParameterlessLocalTrooper(trooper).setAsync('new_val_paramless'),
          throwsA(isA<TrooperStorageException>()),
        );

        await trooper.dispose();
      },
    );

    test(
      'resetAsync awaits storage and throws TrooperStorageException on delete failure',
      () async {
        final storage = ThrowingStorageBackend(failDelete: true);
        final trooper = LocalTrooper<String, ()>(
          namespace: 'async_delete_local',
          initialValue: 'init',
          codec: TrooperCodec.string,
          config: TrooperConfig(storage: storage),
        );

        await expectLater(
          trooper.resetAsync(const ()),
          throwsA(
            isA<TrooperStorageException>().having(
              (e) => e.message,
              'message',
              contains('Failed to delete persisted state'),
            ),
          ),
        );

        // Parameterless variant
        await expectLater(
          ParameterlessLocalTrooper(trooper).resetAsync(),
          throwsA(isA<TrooperStorageException>()),
        );

        await trooper.dispose();
      },
    );
  });

  group('TrooperStorageException in KeyedLocalTrooper', () {
    test(
      'setKey throws TrooperCodecException when codec fails to encode value',
      () {
        final trooper = KeyedLocalTrooper<String, String, ()>(
          namespace: 'failing_codec_keyed',
          initialValue: 'init',
          codec: failingCodec,
          config: TrooperConfig(storage: InMemoryStorageBackend()),
        );

        expect(
          () => trooper.setKey('k1', 'THROW', const ()),
          throwsA(
            isA<TrooperCodecException>().having(
              (e) => e.message,
              'message',
              contains('Failed to encode'),
            ),
          ),
        );

        trooper.dispose();
      },
    );

    test(
      'setKeyAsync awaits storage and throws TrooperStorageException on write failure',
      () async {
        final storage = ThrowingStorageBackend(failWrite: true);
        final trooper = KeyedLocalTrooper<String, String, ()>(
          namespace: 'async_write_keyed',
          initialValue: 'init',
          codec: TrooperCodec.string,
          config: TrooperConfig(storage: storage),
        );

        await expectLater(
          trooper.setKeyAsync('k1', 'new_val', const ()),
          throwsA(
            isA<TrooperStorageException>().having(
              (e) => e.message,
              'message',
              contains('Failed to persist state'),
            ),
          ),
        );

        // Parameterless variant
        await expectLater(
          ParameterlessKeyedLocalTrooper(
            trooper,
          ).setKeyAsync('k1', 'new_val_paramless'),
          throwsA(isA<TrooperStorageException>()),
        );

        await trooper.dispose();
      },
    );

    test(
      'resetKeyAsync awaits storage and throws TrooperStorageException on delete failure',
      () async {
        final storage = ThrowingStorageBackend(failDelete: true);
        final trooper = KeyedLocalTrooper<String, String, ()>(
          namespace: 'async_delete_keyed',
          initialValue: 'init',
          codec: TrooperCodec.string,
          config: TrooperConfig(storage: storage),
        );

        await expectLater(
          trooper.resetKeyAsync('k1', const ()),
          throwsA(
            isA<TrooperStorageException>().having(
              (e) => e.message,
              'message',
              contains('Failed to delete persisted state'),
            ),
          ),
        );

        // Parameterless variant
        await expectLater(
          ParameterlessKeyedLocalTrooper(trooper).resetKeyAsync('k1'),
          throwsA(isA<TrooperStorageException>()),
        );

        await trooper.dispose();
      },
    );
  });
}
