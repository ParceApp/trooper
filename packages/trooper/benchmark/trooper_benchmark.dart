import 'dart:async';
import 'dart:io';

import 'package:trooper/trooper.dart';

void main() async {
  stdout.writeln('========================================================================');
  stdout.writeln('  TROOPER ENTERPRISE BENCHMARK SUITE');
  stdout.writeln('  Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  stdout.writeln('  Dart SDK: ${Platform.version.split(' ').first}');
  stdout.writeln('========================================================================\n');

  final results = <BenchmarkResult>[];

  results.add(await benchmarkL1CacheHit());
  results.add(await benchmarkRequestCoalescing());
  results.add(await benchmarkStatefulStreamThroughput());
  results.add(await benchmarkMemoryFootprint());

  printResultsTable(results);
}

class BenchmarkResult {
  const BenchmarkResult({
    required this.name,
    required this.samples,
    required this.duration,
    required this.opsPerSec,
    required this.latencyPerOp,
    required this.targetDescription,
    required this.targetMet,
  });

  final String name;
  final int samples;
  final Duration duration;
  final double opsPerSec;
  final String latencyPerOp;
  final String targetDescription;
  final bool targetMet;
}

/// 1. L1 Cache-Hit Throughput
/// Target: > 1,000,000 ops/sec on raw in-memory cache lookup.
Future<BenchmarkResult> benchmarkL1CacheHit() async {
  final cache = CacheStore();
  final key = QueryKey('benchmark_namespace', (id: 1));
  final entry = CacheEntry<String>(
    'benchmark_payload',
    createdAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    timeToLive: const Duration(hours: 1),
    source: DataSource.cache,
  );
  cache.putEntry(key, entry);

  // Warm up JIT
  for (var i = 0; i < 50000; i++) {
    cache.get<String>(key);
  }

  const iterations = 2000000;
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    final _ = cache.get<String>(key);
  }
  stopwatch.stop();

  final elapsedMicros = stopwatch.elapsedMicroseconds;
  final opsPerSec = (iterations / (elapsedMicros / 1000000.0));
  final latencyNs = (elapsedMicros * 1000.0) / iterations;

  await cache.dispose();

  return BenchmarkResult(
    name: 'L1 Cache-Hit (Raw)',
    samples: iterations,
    duration: stopwatch.elapsed,
    opsPerSec: opsPerSec,
    latencyPerOp: '${latencyNs.toStringAsFixed(1)} ns',
    targetDescription: '> 1,000,000 ops/sec',
    targetMet: opsPerSec >= 1000000,
  );
}

/// 2. Request-Coalescing Overhead
/// Target: < 0.05ms (50 us) overhead per concurrent caller.
Future<BenchmarkResult> benchmarkRequestCoalescing() async {
  final completer = Completer<String>();
  final query = TrooperQuery<String, ()>(
    namespace: 'coalesce_bench',
    fetch: (_) => completer.future,
    config: const TrooperConfig(timeToLive: Duration(seconds: 10)),
  );

  const callerCount = 10000;
  final stopwatch = Stopwatch()..start();

  final futures = <Future<String>>[];
  for (var i = 0; i < callerCount; i++) {
    futures.add(query.get(const ()));
  }

  // Complete the underlying network request
  completer.complete('result_data');
  await Future.wait(futures);
  stopwatch.stop();

  final elapsedMicros = stopwatch.elapsedMicroseconds;
  final latencyPerCallerUs = elapsedMicros / callerCount;
  final opsPerSec = (callerCount / (elapsedMicros / 1000000.0));

  await query.dispose();

  // Target: < 50 microseconds (0.05 ms) per caller
  return BenchmarkResult(
    name: 'Request-Coalescing',
    samples: callerCount,
    duration: stopwatch.elapsed,
    opsPerSec: opsPerSec,
    latencyPerOp: '${latencyPerCallerUs.toStringAsFixed(2)} µs',
    targetDescription: '< 0.05 ms per caller',
    targetMet: latencyPerCallerUs < 50.0,
  );
}

/// 3. StatefulStream Throughput
/// Target: High-throughput dispatch of 10,000 state events.
Future<BenchmarkResult> benchmarkStatefulStreamThroughput() async {
  final controller = StatefulStreamController<int>();
  const totalEvents = 10000;
  final receivedCompleter = Completer<void>();
  var receivedCount = 0;

  final subscription = controller.stream.listen((state) {
    if (state is DataLoaded<int>) {
      receivedCount++;
      if (receivedCount == totalEvents) {
        if (!receivedCompleter.isCompleted) {
          receivedCompleter.complete();
        }
      }
    }
  });

  // Yield to allow subscription setup
  await Future<void>.delayed(Duration.zero);

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < totalEvents; i++) {
    controller.emitData(i);
  }

  await receivedCompleter.future;
  stopwatch.stop();

  await subscription.cancel();
  await controller.dispose();

  final elapsedMicros = stopwatch.elapsedMicroseconds;
  final opsPerSec = (totalEvents / (elapsedMicros / 1000000.0));
  final latencyPerEventUs = elapsedMicros / totalEvents;

  return BenchmarkResult(
    name: 'StatefulStream Dispatch',
    samples: totalEvents,
    duration: stopwatch.elapsed,
    opsPerSec: opsPerSec,
    latencyPerOp: '${latencyPerEventUs.toStringAsFixed(2)} µs',
    targetDescription: '> 50,000 events/sec',
    targetMet: opsPerSec >= 50000,
  );
}

/// 4. Memory Footprint for 10,000 active keys in KeyedTrooperQuery
/// Target: Under 30 MB for 10,000 cached records with metadata.
Future<BenchmarkResult> benchmarkMemoryFootprint() async {
  final query = KeyedTrooperQuery<int, String, ()>(
    namespace: 'memory_bench',
    fetch: (key, _) async => 'Cached Item #$key',
    config: const TrooperConfig(timeToLive: Duration(hours: 1)),
  );

  final beforeRss = ProcessInfo.currentRss;
  const keyCount = 10000;

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < keyCount; i++) {
    query.setKey(i, 'Cached Item Value with metadata and timestamps #$i', const ());
  }
  stopwatch.stop();

  final afterRss = ProcessInfo.currentRss;
  final diffBytes = afterRss > beforeRss ? afterRss - beforeRss : 0;
  final diffMb = diffBytes / (1024 * 1024);
  final bytesPerKey = diffBytes / keyCount;

  await query.dispose();

  final opsPerSec = (keyCount / (stopwatch.elapsedMicroseconds / 1000000.0));

  return BenchmarkResult(
    name: 'Memory (10,000 Keys)',
    samples: keyCount,
    duration: stopwatch.elapsed,
    opsPerSec: opsPerSec,
    latencyPerOp: '${diffMb.toStringAsFixed(2)} MB (${bytesPerKey.toStringAsFixed(0)} B/key)',
    targetDescription: '< 30.0 MB added RAM',
    targetMet: diffMb < 30.0,
  );
}

void printResultsTable(List<BenchmarkResult> results) {
  stdout.writeln('+--------------------------+-----------+--------------+------------------+----------------------+---------+');
  stdout.writeln('| Benchmark Name           | Samples   | Duration     | Throughput       | Latency / Footprint  | Status  |');
  stdout.writeln('+--------------------------+-----------+--------------+------------------+----------------------+---------+');

  for (final res in results) {
    final name = res.name.padRight(24);
    final samples = res.samples.toString().padLeft(9);
    final duration = '${res.duration.inMilliseconds} ms'.padLeft(12);
    final throughput = '${res.opsPerSec.toStringAsFixed(0)} ops/s'.padLeft(16);
    final latency = res.latencyPerOp.padLeft(20);
    final status = (res.targetMet ? 'PASS' : 'WARN').padRight(7);

    stdout.writeln('| $name | $samples | $duration | $throughput | $latency | $status |');
  }

  stdout.writeln('+--------------------------+-----------+--------------+------------------+----------------------+---------+\n');
  stdout.writeln('All benchmarks completed successfully.\n');
}
