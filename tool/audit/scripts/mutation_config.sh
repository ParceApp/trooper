#!/usr/bin/env bash
# Generates one mutation_test XML per module group with a targeted test command.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
OUT="$ROOT/tool/audit/mutation"; mkdir -p "$OUT"
gen() { # <name> <dir under lib/src> <test args>
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<mutations version="1.2">'
    echo '  <files>'
    for f in "$ROOT/packages/trooper/lib/src/$2"/*.dart; do echo "    <file>lib/src/$2/$(basename "$f")</file>"; done
    echo '  </files>'
    echo '  <commands>'
    echo "    <command group=\"test\" expected-return=\"0\" working-directory=\".\" timeout=\"120\">dart test $3</command>"
    echo '  </commands>'
    echo '</mutations>'
  } > "$OUT/$1.xml"
}
gen concurrency concurrency "test/concurrency test/edge_cases test/config"
gen storage storage "test/storage test/concurrency/cache_store_test.dart test/error test/edge_cases/io_storage_failure_test.dart"
gen core core "test/core test/edge_cases test/error"
gen controller controller "test/controller test/edge_cases/controller_disposal_in_flight_test.dart"
