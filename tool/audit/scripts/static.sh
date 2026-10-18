#!/usr/bin/env bash
# Analyzer with very_good_analysis + strict modes as an overlay, and formatting.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source tool/audit/scripts/lib.sh
RAW="${AUDIT_RAW:-docs/audit/raw}"
trap 'git checkout -- analysis_options.yaml' EXIT
cp tool/audit/analysis_options.audit.yaml analysis_options.yaml
run_step analyze_vga dart analyze --format=machine packages
grep '|' "$RAW/analyze_vga.txt" | cut -d'|' -f1,3 | sort | uniq -c | sort -rn > "$RAW/analyze_vga_summary.txt" || true
run_step format dart format --output=none --set-exit-if-changed packages
