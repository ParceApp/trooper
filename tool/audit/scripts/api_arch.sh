#!/usr/bin/env bash
# Public API inventory, class modifiers, import graph and complexity metrics.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
source tool/audit/scripts/lib.sh
RAW="$ROOT/docs/audit/raw"
export AUDIT_RAW="$RAW"
for pkg in trooper trooper_bloc; do
  run_step "api_$pkg" dart pub global run dart_apitool:main extract \
    --input "packages/$pkg" --output "$RAW/api_$pkg.json" --set-exit-on-missing-export
  run_step "lakos_$pkg" dart pub global run lakos "packages/$pkg" --metrics --format=json \
    -i "{test,example,benchmark,build,doc,skills,coverage}/**" -o "$RAW/lakos_$pkg.json"
  run_step "metrics_$pkg" dart pub global run dart_code_linter:metrics analyze "packages/$pkg/lib" \
    --cyclomatic-complexity=15 --reporter=json --json-path="$RAW/metrics_$pkg.json"
done
(cd tool/audit && dart run bin/class_modifiers.dart ../../packages/trooper/lib ../../packages/trooper_bloc/lib) \
  > "$RAW/class_modifiers.txt"
find packages/*/lib -name '*.dart' -print0 | xargs -0 wc -l | sort -rn > "$RAW/file_sizes.txt"
