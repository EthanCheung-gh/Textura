#!/usr/bin/env bash
# Build the executable as target/release/bin/textura.
#   scripts/build.sh           incremental (fast iteration)
#   CLEAN=1 scripts/build.sh   full rebuild (proves a from-scratch build)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$TEXTURA_CANGJIE_ROOT"
if [ "${CLEAN:-0}" = "1" ]; then
  cjpm build -j "${JOBS:-$(nproc)}" -o textura "$@"
else
  cjpm build -i -j "${JOBS:-$(nproc)}" -o textura "$@"
fi
