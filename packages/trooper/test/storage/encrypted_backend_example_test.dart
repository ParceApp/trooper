import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

// Copy of the README example "Persistence & Sensitive Data".
/// Encrypts values (not keys) before they reach [inner].
class EncryptedStorageBackend implements StorageBackend {
  EncryptedStorageBackend(
    this.inner, {
    required this.encrypt,
    required this.decrypt,
  });

  final StorageBackend inner;

  /// E.g. AES-GCM with a key from the platform keystore (package:cryptography).
  final Future<String> Function(String plainText) encrypt;
  final Future<String> Function(String cipherText) decrypt;

  @override
  Future<String?> read(String key) async {
    final stored = await inner.read(key);
    return stored == null ? null : decrypt(stored);
  }

  @override
  Future<void> write(String key, String value) async =>
      inner.write(key, await encrypt(value));

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<Set<String>> getAllKeys() => inner.getAllKeys();
}

void main() {
  test(
    'README encrypting backend: values encrypted, failures refetched',
    () async {
      final inner = InMemoryStorageBackend();
      var failDecrypt = false;
      final backend = EncryptedStorageBackend(
        inner,
        encrypt: (v) async => v.split('').reversed.join(),
        decrypt: (v) async {
          if (failDecrypt) throw StateError('wrong key');
          return v.split('').reversed.join();
        },
      );
      final hub = TelemetryHub.isolated();
      final events = <TrooperEvent>[];
      hub.events.listen(events.add);
      QueryTrooper<String, ()> query() => QueryTrooper<String, ()>(
        namespace: 'secret',
        fetch: (_) async => 'token-123',
        codec: TrooperCodec.string,
        config: TrooperConfig(storage: backend),
        telemetry: hub,
      );

      final first = query();
      await first.get(());
      await pumpEventQueue();
      final key = const QueryKey('secret', ()).storageKey;
      expect(await inner.read(key), isNot(contains('token-123')));
      expect((await backend.read(key))!, contains('token-123'));
      await first.dispose();

      failDecrypt = true;
      final second = query();
      expect(await second.get(()), 'token-123');
      await pumpEventQueue();
      expect(events.whereType<PersistenceErrorEvent>(), isNotEmpty);
      await second.dispose();
    },
  );
}
