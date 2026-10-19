import 'dart:async';
import 'dart:io';
import 'package:trooper/trooper.dart';

/// In-memory mock implementation of [StorageBackend] with inspection and fault-injection hooks.
class MockStorageBackend implements StorageBackend {
  MockStorageBackend({
    this.readDelay,
    this.writeDelay,
    this.failOnRead = false,
    this.failOnWrite = false,
  });

  final Map<String, String> _data = {};

  Duration? readDelay;
  Duration? writeDelay;
  bool failOnRead;
  bool failOnWrite;

  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;

  Map<String, String> get entries => Map.unmodifiable(_data);

  @override
  Future<String?> read(String key) async {
    readCount++;
    if (failOnRead) {
      throw const FileSystemException('Simulated disk read failure');
    }
    if (readDelay != null) {
      await Future<void>.delayed(readDelay!);
    }
    return _data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    if (failOnWrite) {
      throw const FileSystemException('Simulated disk full / write failure');
    }
    if (writeDelay != null) {
      await Future<void>.delayed(writeDelay!);
    }
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteCount++;
    _data.remove(key);
  }

  @override
  Future<Set<String>> getAllKeys() async => Set.unmodifiable(_data.keys);

  void reset() {
    _data.clear();
    readCount = 0;
    writeCount = 0;
    deleteCount = 0;
    failOnRead = false;
    failOnWrite = false;
  }
}
