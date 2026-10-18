// Audit (PERF-03): cost of telemetry on the QueryTrooper cache-hit path.
import 'dart:io';

import 'package:trooper/trooper.dart';

Future<int> _run({required bool listen, int n = 300000}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  final hub = TelemetryHub.isolated();
  final sub = listen ? hub.events.listen((_) {}) : null;
  final q = QueryTrooper<int, ()>(
    namespace: 'perf03',
    fetch: (_) async => 1,
    telemetry: hub,
  );
  await q.get(()); // warm the cache
  for (var i = 0; i < 20000; i++) {
    await q.get(());
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await q.get(());
  }
  sw.stop();
  await sub?.cancel();
  await q.dispose();
  return sw.elapsedMicroseconds * 1000 ~/ n; // ns per get
}

Future<void> main() async {
  final off = <int>[], on = <int>[];
  for (var round = 0; round < 5; round++) {
    off.add(await _run(listen: false));
    on.add(await _run(listen: true));
  }
  off.sort();
  on.sort();
  final mOff = off[2], mOn = on[2];
  stdout
    ..writeln('cache-hit get without listener: median $mOff ns (runs $off)')
    ..writeln('cache-hit get with listener:    median $mOn ns (runs $on)')
    ..writeln('overhead with listener: ${((mOn - mOff) * 100 / mOff).toStringAsFixed(1)} %');
}
