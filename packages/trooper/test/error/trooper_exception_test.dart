import 'package:test/test.dart';
import 'package:trooper/trooper.dart';

void main() {
  group('TrooperException Hierarchy', () {
    test('TrooperCancelledException message and toString', () {
      const cancel = TrooperCancelledException(message: 'Request was aborted.');
      expect(cancel.message, 'Request was aborted.');
      expect(
        cancel.toString(),
        'TrooperCancelledException: Request was aborted.',
      );

      final cancelWithError = TrooperCancelledException(
        message: 'Aborted',
        error: 'Reason: token cancelled',
      );
      expect(
        cancelWithError.toString(),
        'TrooperCancelledException: Aborted (Error: Reason: token cancelled)',
      );
    });

    test('TrooperTimeoutException elapsed timeout and formatting', () {
      final timeout = TrooperTimeoutException(
        timeout: const Duration(seconds: 5),
      );
      expect(timeout.timeout, const Duration(seconds: 5));
      expect(
        timeout.toString(),
        contains(
          'TrooperTimeoutException: The operation timed out after 5000 ms.',
        ),
      );

      final customTimeout = TrooperTimeoutException(
        timeout: const Duration(seconds: 2),
        message: 'Custom timeout message',
      );
      expect(customTimeout.toString(), contains('Custom timeout message'));
    });

    test('TrooperStorageException formatting and underlying error', () {
      const storageEx = TrooperStorageException(
        'Failed to read key',
        error: 'Disk I/O error',
      );
      expect(
        storageEx.toString(),
        'TrooperStorageException: Failed to read key (Error: Disk I/O error)',
      );
    });
  });
}
