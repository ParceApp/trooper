#!/usr/bin/env bash
# Mutation testing in a detached scratch worktree, because mutation_test edits
# source files in place. Usage: mutation.sh <worktree-dir> [group...]
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"
WT="$1"; shift
GROUPS_TO_RUN=("${@:-concurrency storage core controller}")
RAW="$ROOT/docs/audit/raw/mutation"; mkdir -p "$RAW"
if [ ! -d "$WT" ]; then
  git -C "$ROOT" worktree add --detach "$WT" main
  (cd "$WT" && flutter pub get >/dev/null)
fi
cd "$WT/packages/trooper"
# Coverage of the worktree copy lets mutation_test skip uncovered lines quickly.
dart pub global run coverage:test_with_coverage --out "$RAW/cov" >/dev/null 2>&1
for g in ${GROUPS_TO_RUN[@]}; do
  start=$SECONDS
  dart pub global run mutation_test:mutation_test \
    --coverage "$RAW/cov/lcov.info" -o "$RAW/$g" "$ROOT/tool/audit/mutation/$g.xml" \
    > "$RAW/$g.txt" 2>&1
  echo "$? $((SECONDS-start))s" > "$RAW/$g.exit"
done
git -C "$WT" status --porcelain > "$RAW/worktree_status.txt"
