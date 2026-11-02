#!/usr/bin/env bash
# Three-tier parity acceptance gate (docs/PARITY.md §2.1).
#
#   structure: long-rule error <=1.5px, global shift == (0,0), edge coverage >=90%
#   visual:    1px-Gaussian-blurred SSIM >=0.95
#   raw:       pixels with ΔRGB<=32 >=95%
#
# Compares tools/parity/ref against tools/parity/out by default, prints a table
# and writes tools/parity/out/gate-report.json. Exit 0 = all selected pairs pass,
# 1 = a tier failed, 2 = usage/input error. For side-by-side and heatmap images
# use tools/parity/diff.py (localisation only, not the verdict).
#
#   scripts/diff.sh                              # both themes, all 7 routes
#   scripts/diff.sh --theme light
#   scripts/diff.sh --route settings --theme dark
#   scripts/diff.sh --route dashboard --route gantt
#   scripts/diff.sh --ref path/to/ref --out path/to/out --json report.json
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF="$ROOT/tools/parity/ref"
OUT="$ROOT/tools/parity/out"
JSON="$OUT/gate-report.json"
THEME="both"
ROUTES=()

usage() {
  cat <<'EOF'
Usage: scripts/diff.sh [options]

  --theme light|dark|both   theme filter (default: both)
  --route NAME              route filter; repeatable or comma-separated
                            (dashboard|calendar|okr|gtd|gantt|sop|settings)
  --ref PATH                reference dir/file (default: tools/parity/ref)
  --out PATH                candidate dir/file (default: tools/parity/out)
  --json PATH               JSON report path (default: tools/parity/out/gate-report.json)
  -h, --help                show this help

Legacy form: scripts/diff.sh <light|dark|both> selects the theme.

Exit codes: 0 = all selected pairs pass; 1 = at least one tier failed;
            2 = usage error / missing input / no pair matched.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)
      THEME="${2:?--theme needs a value}"
      shift 2
      ;;
    --theme=*)
      THEME="${1#*=}"
      shift
      ;;
    --route)
      ROUTES+=("${2:?--route needs a value}")
      shift 2
      ;;
    --route=*)
      ROUTES+=("${1#*=}")
      shift
      ;;
    --ref)
      REF="${2:?--ref needs a value}"
      shift 2
      ;;
    --ref=*)
      REF="${1#*=}"
      shift
      ;;
    --out)
      OUT="${2:?--out needs a value}"
      shift 2
      ;;
    --out=*)
      OUT="${1#*=}"
      shift
      ;;
    --json)
      JSON="${2:?--json needs a value}"
      shift 2
      ;;
    --json=*)
      JSON="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    light|dark|both)
      THEME="$1"
      shift
      ;;
    *)
      echo "diff.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$THEME" in
  light|dark|both) ;;
  *)
    echo "diff.sh: --theme must be light, dark or both (got '$THEME')" >&2
    exit 2
    ;;
esac

args=(--ref "$REF" --out "$OUT" --theme "$THEME" --json "$JSON")
for route in ${ROUTES[@]+"${ROUTES[@]}"}; do
  args+=(--route "$route")
done

python3 "$ROOT/tools/parity/gate.py" "${args[@]}"
