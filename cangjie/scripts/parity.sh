#!/usr/bin/env bash
# Render the CUI parity screenshots into tools/parity/out/.
#
#   scripts/parity.sh                       # light, all 7 routes
#   scripts/parity.sh --theme both          # 14 screenshots
#   scripts/parity.sh --theme dark --route settings
#   TEXTURA_PARITY_THEMES="light dark" scripts/parity.sh
#   TEXTURA_PARITY_ROUTES="dashboard gantt" scripts/parity.sh
#
# The settings view ellipsizes the --workspace path onto one line (commit a0c7a81),
# so the screenshots no longer depend on the build directory's path length.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$TEXTURA_CANGJIE_ROOT"

BIN="$TEXTURA_CANGJIE_ROOT/target/release/bin/textura"
WORKSPACE="$TEXTURA_CANGJIE_ROOT/tools/parity/workspace.json"
OUT="$TEXTURA_CANGJIE_ROOT/tools/parity/out"
ALL_ROUTES=(dashboard calendar okr gtd gantt sop settings)
THEMES="${TEXTURA_PARITY_THEMES:-light}"
ROUTES=(${TEXTURA_PARITY_ROUTES:-${ALL_ROUTES[*]}})
ROUTES_SET=0
# Window/canvas size (logical pixels). The pixel gate always compares the 1440x900 set;
# the other sizes are used for the responsive-layout review (docs/DEVICE-NOTES.md §18).
WIDTH="${TEXTURA_PARITY_WIDTH:-1440}"
HEIGHT="${TEXTURA_PARITY_HEIGHT:-900}"

usage() {
  cat <<'EOF'
Usage: scripts/parity.sh [options]

  --theme light|dark|both   theme(s) to render; "both" = light + dark (default: light,
                            or $TEXTURA_PARITY_THEMES)
  --route NAME              route filter; repeatable or comma-separated
                            (default: all 7, or $TEXTURA_PARITY_ROUTES)
  --out PATH                output directory (default: tools/parity/out)
  --width N                 window width in logical pixels (default 1440)
  --height N                window height in logical pixels (default 900)
  -h, --help                show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --theme)
      THEMES="${2:?--theme needs a value}"
      shift 2
      ;;
    --theme=*)
      THEMES="${1#*=}"
      shift
      ;;
    --route)
      if [[ "$ROUTES_SET" -eq 0 ]]; then
        ROUTES=()
        ROUTES_SET=1
      fi
      ROUTES+=("${2:?--route needs a value}")
      shift 2
      ;;
    --route=*)
      if [[ "$ROUTES_SET" -eq 0 ]]; then
        ROUTES=()
        ROUTES_SET=1
      fi
      ROUTES+=("${1#*=}")
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
    --width)
      WIDTH="${2:?--width needs a value}"
      shift 2
      ;;
    --height)
      HEIGHT="${2:?--height needs a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "parity.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$THEMES" in
  both) THEMES="light dark" ;;
  light|dark|"light dark"|"dark light") ;;
  *)
    echo "parity.sh: --theme must be light, dark or both (got '$THEMES')" >&2
    exit 2
    ;;
esac

# Accept comma-separated route lists from --route and $TEXTURA_PARITY_ROUTES.
_normalized=()
for item in "${ROUTES[@]}"; do
  for part in ${item//,/ }; do
    _normalized+=("$part")
  done
done
ROUTES=("${_normalized[@]}")
for route in "${ROUTES[@]}"; do
  if [[ ! " ${ALL_ROUTES[*]} " == *" $route "* ]]; then
    echo "parity.sh: unknown route '$route' (expected: ${ALL_ROUTES[*]})" >&2
    exit 2
  fi
done

[[ -x "$BIN" ]] || { echo "missing $BIN (run scripts/build.sh)" >&2; exit 2; }
[[ -f "$WORKSPACE" ]] || { echo "missing $WORKSPACE (run tools/parity/capture_ref.mjs)" >&2; exit 2; }
mkdir -p "$OUT"

for theme in $THEMES; do
  for route in "${ROUTES[@]}"; do
    echo "== $route-$theme"
    xvfb-run -a -s "-screen 0 ${WIDTH}x${HEIGHT}x24" \
      "$BIN" --workspace "$WORKSPACE" --route "$route" --theme "$theme" \
      --width "$WIDTH" --height "$HEIGHT" --snapshot "$OUT/$route-$theme.png"
  done
done
