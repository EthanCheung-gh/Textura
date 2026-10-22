#!/usr/bin/env bash
# Diff tools/parity/ref against tools/parity/out. Non-zero when a pair exceeds tolerance.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="${1:-light}"
python3 "$ROOT/tools/parity/diff.py" \
  "$ROOT/tools/parity/ref" \
  "$ROOT/tools/parity/out" \
  --report-dir "$ROOT/tools/parity/out/diffs" \
  --theme "$THEME" \
  --json "$ROOT/tools/parity/out/diff-report-$THEME.json"
