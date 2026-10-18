import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _runStep(String raw, String command) => Process.run(
      'bash',
      ['-c', 'source scripts/lib.sh; AUDIT_RAW="$raw" run_step demo $command'],
    );

void main() {
  late Directory raw;
  setUp(() async => raw = await Directory.systemTemp.createTemp('audit_raw'));
  tearDown(() => raw.delete(recursive: true));

  test('run_step records non-zero exit', () async {
    final result = await _runStep(raw.path, 'false');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File('${raw.path}/demo.exit').readAsStringSync().trim(), '1');
  });

  test('run_step records zero exit and captures output', () async {
    final result = await _runStep(raw.path, 'echo hello');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(File('${raw.path}/demo.exit').readAsStringSync().trim(), '0');
    expect(File('${raw.path}/demo.txt').readAsStringSync(), contains('hello'));
  });
}
