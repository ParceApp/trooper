#!/usr/bin/env bash
# Line and branch coverage for both packages, plus inventory of real delays in tests.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
source tool/audit/scripts/lib.sh
RAW="$ROOT/docs/audit/raw"
export AUDIT_RAW="$RAW"
(cd packages/trooper && run_step coverage_trooper \
  dart pub global run coverage:test_with_coverage --branch-coverage --out "$RAW/coverage_trooper")
(cd packages/trooper_bloc && mkdir -p "$RAW/coverage_bloc" && run_step coverage_bloc \
  flutter test --coverage --branch-coverage --coverage-path "$RAW/coverage_bloc/lcov.info")
{
  echo "trooper:";      (cd tool/audit && dart run bin/lcov_summary.dart "$RAW/coverage_trooper/lcov.info")
  echo "trooper_bloc:"; (cd tool/audit && dart run bin/lcov_summary.dart "$RAW/coverage_bloc/lcov.info")
} > "$RAW/coverage_summary.txt"
grep -rnE "Future(<void>)?\.delayed|sleep\(" packages/*/test > "$RAW/real_delays.txt" || true
