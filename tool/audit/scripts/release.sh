#!/usr/bin/env bash
# pana, publish dry-run, dartdoc, OSV scan, benchmark baseline, package contents.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
source tool/audit/scripts/lib.sh
RAW="$ROOT/docs/audit/raw"
export AUDIT_RAW="$RAW"
for pkg in trooper trooper_bloc; do
  run_step "pana_$pkg" pana --no-warning --json "packages/$pkg"
done
(cd packages/trooper && run_step dryrun_trooper dart pub publish --dry-run)
(cd packages/trooper_bloc && run_step dryrun_bloc flutter pub publish --dry-run)
(cd packages/trooper && run_step dartdoc_trooper dart doc --output "$RAW/dartdoc_trooper")
(cd packages/trooper_bloc && run_step dartdoc_bloc dart doc --output "$RAW/dartdoc_bloc")
run_step osv osv-scanner scan -L pubspec.lock
for i in 1 2 3; do
  (cd packages/trooper && run_step "bench_run$i" dart run benchmark/trooper_benchmark.dart)
done
# Files > 500 KB in the dry-run file listings
grep -hE "\([0-9.]+ (KB|MB)\)" "$RAW/dryrun_trooper.txt" "$RAW/dryrun_bloc.txt" > "$RAW/package_contents.txt" || true
