#!/usr/bin/env bash
# Shared helpers for audit scripts.

# run_step <name> <command...>
# Runs the command, writes stdout+stderr to $AUDIT_RAW/<name>.txt and the exit
# code to $AUDIT_RAW/<name>.exit. Always returns 0 so later steps still run.
run_step() {
  local name="$1"; shift
  local raw="${AUDIT_RAW:-docs/audit/raw}"
  mkdir -p "$raw"
  local code=0
  "$@" >"$raw/$name.txt" 2>&1 || code=$?
  echo "$code" >"$raw/$name.exit"
  echo "[$name] exit $code"
  return 0
}
