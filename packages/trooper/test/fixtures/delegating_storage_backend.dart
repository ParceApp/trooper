import 'package:trooper/trooper.dart';

/// [StorageBackend] delegating to an [InMemoryStorageBackend]; extend it to
/// inject faults in single methods.
abstract class DelegatingStorageBackend implements StorageBackend {
  /// The wrapped in-memory backend.
  final InMemoryStorageBackend inner = InMemoryStorageBackend();

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String value) => inner.write(key, value);

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<Set<String>> getAllKeys() => inner.getAllKeys();
}
