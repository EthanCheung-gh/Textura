#!/usr/bin/env bash
# Cross-build the Textura Cangjie host for aarch64-linux-ohos.
#
# What it does, in order:
#   1. refresh the build snapshot from the shared worktree (never builds in place)
#   2. point the Cangjie SDL bindings at the vendored aarch64-linux-ohos SDL3/SDL3_ttf
#   3. activate the ohos cross toolchain (cjv envsetup sts-1.2.0 --target ohos)
#   4. cjpm build --target aarch64-linux-ohos in cangjie/harmony/host
#   5. prove the artifact: ELF arch, SONAME, SDL_App* in .dynsym, NEEDED list
#
# SDL3/SDL3_ttf are NOT rebuilt here: the vendored .sdl3-ohos pair is the pinned aarch64-linux-ohos
# build already used by the reference project. Rebuilding them is only needed if a library is
# missing; see cangjie/docs/HARMONY.md §8.
#
# Usage: cangjie/scripts/harmony/build_ohos.sh [--no-sync]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

SYNC=1
[ "${1:-}" = "--no-sync" ] && SYNC=0

command -v rsync >/dev/null || die "rsync is required"
command -v file >/dev/null || die "file is required"
require_tmp_space

[ "$SYNC" = 1 ] && sync_snapshot
require_file "$SNAP_HARMONY/host/cjpm.toml" "run from the Textura worktree"

# Diagnostic build (`TEXTURA_PROBE=1`): compile the on-device probe in. The worktree default stays
# `PROBE_COMPILED_ON = false` — the flip happens in the snapshot only, so a shipping build is
# never at risk and a diagnostic build stays reproducible with one command (docs/STABILITY.md).
if [ "${TEXTURA_PROBE:-0}" = "1" ]; then
  PROBE_SRC="$SNAP_HARMONY/host/src/probe.cj"
  require_file "$PROBE_SRC" "probe source missing from snapshot"
  sed -i 's/^private let PROBE_COMPILED_ON: Bool = false$/private let PROBE_COMPILED_ON: Bool = true/' \
    "$PROBE_SRC"
  grep -q '^private let PROBE_COMPILED_ON: Bool = true$' "$PROBE_SRC" ||
    die "could not enable PROBE_COMPILED_ON in $PROBE_SRC"
  log "probe: PROBE_COMPILED_ON = true (diagnostic build; worktree default stays false)"
fi
stage_ohos_sdl_bindings
provide_crt_objects
stamp_host_sysroot
ohos_env

log "cjc: $(cjc --version | head -1)"
log "cross-building cangjie/harmony/host -> aarch64-linux-ohos"
cd "$HOST_PKG"
cjpm build --target aarch64-linux-ohos

HOST_SO="$HOST_PKG/target/aarch64-linux-ohos/release/textura_host/libtextura_host.so"
require_file "$HOST_SO" "cjpm did not produce the host library"
is_aarch64 "$HOST_SO" || die "$HOST_SO is not aarch64: $(file -b "$HOST_SO")"

log "artifact: $HOST_SO ($(stat -c%s "$HOST_SO") bytes)"
file -b "$HOST_SO"

# Read the dynamic symbol table once: `readelf | grep -q` would close the pipe early and turn a
# match into SIGPIPE/141 under `set -o pipefail`.
SYMS="$(mktemp)"
trap 'rm -f "$SYMS"' EXIT
"$READELF" --dyn-syms "$HOST_SO" >"$SYMS"

log "exported SDL entry points (.dynsym):"
awk '$4=="FUNC" && $5=="GLOBAL" && $8 ~ /^(SDL_AppInit|SDL_AppIterate|SDL_AppEvent|SDL_AppQuit|textura_host_error|textura_host_ready)$/ {print "   ", $8}' "$SYMS"
for sym in SDL_AppInit SDL_AppIterate SDL_AppEvent SDL_AppQuit textura_host_error; do
  grep -q "GLOBAL.* ${sym}\$" "$SYMS" || die "missing exported symbol $sym"
done

log "NEEDED:"
"$READELF" -d "$HOST_SO" | awk '/NEEDED/ {gsub(/[][]/,"",$5); print "   ", $5}'

log "SONAME: $("$READELF" -d "$HOST_SO" | awk '/SONAME/ {gsub(/[][]/,"",$5); print $5}')"
log "done — next: cangjie/scripts/harmony/stage_libs.sh"
