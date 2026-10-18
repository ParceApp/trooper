#!/usr/bin/env bash
# Runs each package's suite N times (default 100) with random test ordering.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
RAW="$ROOT/docs/audit/raw"; mkdir -p "$RAW"
N="${FLAKE_RUNS:-100}"
run_suite() { # <pkg> <cmd...>
  local pkg="$1"; shift
  local out="$RAW/flake_$pkg.txt"; : > "$out"
  local start=$SECONDS
  for i in $(seq 1 "$N"); do
    local seed=$RANDOM$RANDOM
    if ! (cd "$ROOT/packages/$pkg" && "$@" --test-randomize-ordering-seed="$seed" --reporter=failures-only >>"$out.log" 2>&1); then
      echo "RUN $i FAILED seed=$seed" >> "$out"
    fi
  done
  echo "runs=$N failed=$(grep -c FAILED "$out") seconds=$((SECONDS-start))" >> "$out"
}
run_suite trooper dart test
run_suite trooper_bloc flutter test
