#!/usr/bin/env bash
# Extracts the public API of trooper and trooper_bloc into docs/api/.
#
# The committed files are the API baseline. To check a change for API
# differences, run this script and then `git diff --exit-code docs/api/`.
# Requires: dart pub global activate dart_apitool 0.23.2
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
for pkg in trooper trooper_bloc; do
  out="docs/api/$pkg.json"
  dart pub global run dart_apitool:main extract \
    --input "packages/$pkg" --output "$out" --set-exit-on-missing-export
  # The extractor records the path of a temporary copy; make it reproducible.
  sed -i.bak -E "s#\"packagePath\": \"[^\"]*\"#\"packagePath\": \"packages/$pkg\"#" "$out"
  rm "$out.bak"
done
