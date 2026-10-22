#!/usr/bin/env bash
# Render the CUI parity screenshots into tools/parity/out/.
#
#   scripts/parity.sh                 # light, all 7 routes
#   TEXTURA_PARITY_THEMES="light dark" scripts/parity.sh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$TEXTURA_CANGJIE_ROOT"

BIN="$TEXTURA_CANGJIE_ROOT/target/release/bin/textura"
WORKSPACE="$TEXTURA_CANGJIE_ROOT/tools/parity/workspace.json"
OUT="$TEXTURA_CANGJIE_ROOT/tools/parity/out"
THEMES="${TEXTURA_PARITY_THEMES:-light}"
ROUTES="dashboard calendar okr gtd gantt sop settings"

[[ -x "$BIN" ]] || { echo "missing $BIN (run scripts/build.sh)" >&2; exit 2; }
[[ -f "$WORKSPACE" ]] || { echo "missing $WORKSPACE (run tools/parity/capture_ref.mjs)" >&2; exit 2; }
mkdir -p "$OUT"

for theme in $THEMES; do
  for route in $ROUTES; do
    echo "== $route-$theme"
    xvfb-run -a -s "-screen 0 1440x900x24" \
      "$BIN" --workspace "$WORKSPACE" --route "$route" --theme "$theme" \
      --width 1440 --height 900 --snapshot "$OUT/$route-$theme.png"
  done
done
