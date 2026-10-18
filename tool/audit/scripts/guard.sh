#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if ! git diff --quiet main -- packages/trooper/lib packages/trooper_bloc/lib; then
  echo "GUARD: packages/*/lib differs from main" >&2; exit 1
fi
echo "GUARD: ok"
