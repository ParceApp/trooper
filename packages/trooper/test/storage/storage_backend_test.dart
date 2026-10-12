import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('InMemoryStorageBackend', () {
    test(
      'read, write, delete, containsKey, clear, getAllKeys, count',
      () async {
        final storage = InMemoryStorageBackend();
        expect(storage.count, 0);
        expect(await storage.containsKey('key1'), isFalse);
        expect(await storage.read('key1'), isNull);

        await storage.write('key1', 'value1');
        await storage.write('key2', 'value2');

        expect(storage.count, 2);
        expect(await storage.containsKey('key1'), isTrue);
        expect(await storage.read('key1'), 'value1');
        expect(await storage.read('key2'), 'value2');
        expect(await storage.getAllKeys(), {'key1', 'key2'});

        final deleted = await storage.delete('key1');
        expect(deleted, 'value1');
        expect(storage.count, 1);
        expect(await storage.containsKey('key1'), isFalse);
        expect(await storage.read('key1'), isNull);

        final nonExistentDelete = await storage.delete('unknown');
        expect(nonExistentDelete, isNull);

        await storage.clear();
        expect(storage.count, 0);
        expect(await storage.getAllKeys(), isEmpty);
      },
    );
  });
}
