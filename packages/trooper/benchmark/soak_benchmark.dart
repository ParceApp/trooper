// Soak test: 10,000 keys, 1,000,000 mixed operations.
// Prints RSS after a 100,000-operation warm-up and at the end.
import 'dart:io';
import 'dart:math';

import 'package:trooper/trooper.dart';

const _keys = 10000;
const _ops = 1000000;
const _warmup = 100000;

int _mb(int bytes) => bytes ~/ (1024 * 1024);

Future<void> main() async {
  final rnd = Random(42);
  final local = KeyedLocalTrooper<int, int, ()>(
    namespace: 'soak_local',
    initialValue: 0,
  );
  final query = KeyedQueryTrooper<int, int, ()>(
    namespace: 'soak_query',
    fetch: (k, _) async => k,
  );

  var warmupRss = 0;
  final sw = Stopwatch()..start();
  for (var i = 1; i <= _ops; i++) {
    final key = rnd.nextInt(_keys);
    switch (rnd.nextInt(4)) {
      case 0:
        await local[key].get(());
      case 1:
        local.setKey(key, i, ());
      case 2:
        await query[key].get(());
      default:
        query[key].invalidate();
    }
    if (i == _warmup) warmupRss = ProcessInfo.currentRss;
  }
  final endRss = ProcessInfo.currentRss;
  final ratio = endRss / warmupRss;
  stdout
    ..writeln('ops: $_ops, keys: $_keys, seconds: ${sw.elapsed.inSeconds}')
    ..writeln('rss after warm-up: ${_mb(warmupRss)} MB')
    ..writeln('rss at end:        ${_mb(endRss)} MB')
    ..writeln('ratio: ${ratio.toStringAsFixed(3)} (threshold 1.05)')
    ..writeln(
      'cache entries: query=${query.cache.size} local=${local.cache.size}',
    )
    ..writeln(ratio <= 1.05 ? 'RESULT: PASS' : 'RESULT: FAIL');
  await local.dispose();
  await query.dispose();
}
