#!/usr/bin/env bash
# Records the audited commit and tool versions.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source tool/audit/scripts/lib.sh
run_step env_commit git rev-parse main
run_step env_dart dart --version
run_step env_flutter flutter --version
run_step env_chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
run_step env_global_tools dart pub global list
cat docs/audit/raw/env_*.txt > docs/audit/raw/env.txt
