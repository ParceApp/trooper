#!/usr/bin/env bash
# Web (dart2js, dart2wasm) runs for the core package and a lower-bound dependency run.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
source tool/audit/scripts/lib.sh
RAW="$ROOT/docs/audit/raw"
export AUDIT_RAW="$RAW"
if [ "${SKIP_WEB:-0}" != 1 ]; then
  (cd packages/trooper && run_step web_js dart test -p chrome)
  (cd packages/trooper && run_step web_wasm dart test -p chrome --compiler dart2wasm)
fi

# pubspec.lock is gitignored: back it up by copy, never via git.
cp pubspec.lock "$RAW/pubspec.lock.before"
trap 'cd "$ROOT" && cp "$RAW/pubspec.lock.before" pubspec.lock && flutter pub get >/dev/null' EXIT
# 1) All dependencies (incl. dev tooling) at their lower bounds.
run_step downgrade_resolve flutter pub downgrade
flutter pub deps --style=compact > "$RAW/downgrade_versions.txt" 2>&1 || true
(cd packages/trooper && run_step downgrade_trooper dart test)
(cd packages/trooper_bloc && run_step downgrade_bloc flutter test)
# 2) Only runtime dependencies at their lower bounds.
cp "$RAW/pubspec.lock.before" pubspec.lock && flutter pub get >/dev/null
run_step downgrade_runtime_resolve flutter pub downgrade meta flutter_bloc bloc
flutter pub deps --style=compact > "$RAW/downgrade_runtime_versions.txt" 2>&1 || true
(cd packages/trooper && run_step downgrade_runtime_trooper dart test)
(cd packages/trooper_bloc && run_step downgrade_runtime_bloc flutter test)
