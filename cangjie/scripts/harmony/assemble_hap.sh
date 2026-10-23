#!/usr/bin/env bash
# Assemble the Textura HAP and print everything needed to install it once a device is connected.
#
# Prerequisites (run in this order):
#   cangjie/scripts/harmony/build_ohos.sh     -> libtextura_host.so for aarch64-linux-ohos
#   cangjie/scripts/harmony/stage_libs.sh     -> the NEEDED closure + interop runtime in entry/libs
#
# hvigor runs in the snapshot (it writes .hvigor/, oh_modules/, entry/build/). The produced HAP is
# copied back to cangjie/harmony/out/ so it can be inspected from the worktree; that directory is
# git-ignored.
#
# Signing: the `default` product carries the debug signing config, and this project now has material
# issued by AGC for its own bundleName (cangjie/harmony/.certs/textura-debug/, plugged in with
# set_signing_material.sh), so `default` is expected to sign successfully. The fallback below stays
# as a safety net: if `default` fails with 00303074 — the profile's bundleName is not the app's, e.g.
# after the material was replaced by another project's — the script builds the `unsigned` product
# (same module, same SDK versions, no signing material) and prints both outcomes, so the failure is
# never hidden. Installability of the result is stated explicitly at the end; an unsigned HAP is not
# installable and this script does not print an install command for it.
#
# Usage: cangjie/scripts/harmony/assemble_hap.sh [--no-sync]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

SYNC=1
[ "${1:-}" = "--no-sync" ] && SYNC=0

require_tmp_space

if [ "$SYNC" = 1 ]; then
  sync_snapshot
  # The sync deletes entry/libs (it is a build artifact, not tracked in the worktree), so put the
  # staged closure back before hvigor runs. stage_libs.sh is idempotent and cheap.
  "$SCRIPT_DIR/stage_libs.sh"
fi
require_file "$LIBS_DIR/libtextura_host.so" "run stage_libs.sh first"
require_file "$OHOS_LIBS_DIR/libohos.ark_interop.so" "run stage_libs.sh first (interop runtime missing)"
require_file "$SNAP_HARMONY/build-profile.json5" "harmony project missing from snapshot"
require_file "$HVIGORW" "hvigorw not found in the command-line tools"

run_hvigor() {
  local product="$1" log="$2"
  local rc=0
  cd "$SNAP_HARMONY"
  # errexit stays disabled here on purpose: re-enabling it inside the function would make the
  # `return $rc` below abort the script before the caller can inspect rc (the signed product is
  # expected to fail on this machine). The caller restores errexit after capturing the status.
  set +e
  "$HVIGORW" --mode module -p "product=$product" -p buildMode=debug assembleHap --no-daemon \
    >"$log" 2>&1
  rc=$?
  return $rc
}

LOG_DIR="$SNAP_HARMONY/.hvigor/outputs/build-logs"
mkdir -p "$LOG_DIR"

BUNDLE="$(app_bundle_name)"
BUNDLE="${BUNDLE:-com.ethancheung.textura}"

# Report the signing material before the (long) build instead of letting hvigor discover a
# bundleName mismatch as 00303074 twenty minutes later.
SIGN_PROFILE="$(sed -n 's/.*"profile": *"\([^"]*\)".*/\1/p' "$SNAP_HARMONY/build-profile.json5" | head -1)"
if [ -n "$SIGN_PROFILE" ]; then
  PROFILE_BUNDLE="$(profile_bundle_name "$SIGN_PROFILE" || true)"
  log "signing profile: $SIGN_PROFILE"
  log "     profile bundle-name=${PROFILE_BUNDLE:-<unreadable>}  app bundleName=$BUNDLE"
  if [ "$PROFILE_BUNDLE" != "$BUNDLE" ]; then
    warn "the profile's bundleName does not match $BUNDLE, so product=default cannot be signed here"
    warn "  (hvigor 00303074). Supply material for $BUNDLE with"
    warn "  cangjie/scripts/harmony/set_signing_material.sh; see docs/HARMONY.md §7.1"
  fi
fi

log "assembling HAP (product=default, signed) via $HVIGORW"
PRODUCT="default"
SIGNING_NOTE="signed with the debug profile printed above"
set +e
run_hvigor default "$LOG_DIR/assemble-signed.log"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  if grep -q "00303074" "$LOG_DIR/assemble-signed.log"; then
    warn "product=default cannot be signed on this machine:"
    sed -n '/00303074/,/^.*does not match/p' "$LOG_DIR/assemble-signed.log" | sed 's/^/    /' | head -6
    warn "falling back to product=unsigned (same module, same SDK versions, no signing material)"
    PRODUCT="unsigned"
    SIGNING_NOTE="unsigned — installing needs a debug profile issued for com.ethancheung.textura"
    log "assembling HAP (product=unsigned)"
    # run_hvigor leaves errexit off (see its comment), so the status has to be checked by hand —
    # otherwise a failed package step would surface later as the much less useful
    # "no HAP was found". A full /tmp, for example, fails here at PackageHap with
    # "IOException: Disk quota exceeded" and produces exactly that trap.
    set +e
    run_hvigor unsigned "$LOG_DIR/assemble-unsigned.log"
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      warn "hvigorw assembleHap failed (product=unsigned), see $LOG_DIR/assemble-unsigned.log"
      grep -iE "ERROR|Exception|failed" "$LOG_DIR/assemble-unsigned.log" | tail -12 | sed 's/^/    /' || true
      die "HAP not produced (the build itself failed; fix the hvigor error above)"
    fi
  else
    warn "hvigorw assembleHap failed (product=default), see $LOG_DIR/assemble-signed.log"
    tail -25 "$LOG_DIR/assemble-signed.log" | sed 's/^/    /'
    die "HAP not produced"
  fi
fi

HAP_DIR="$SNAP_HARMONY/entry/build/$PRODUCT/outputs/default"
HAP="$HAP_DIR/entry-default-signed.hap"
[ -f "$HAP" ] || HAP="$HAP_DIR/entry-default-unsigned.hap"
[ -f "$HAP" ] || die "no HAP was found under $HAP_DIR — if hvigor reported success, check that /tmp (the snapshot's filesystem) has room for a ~22 MB archive plus its temp copy"

SIGNED=0
case "$(basename "$HAP")" in
  *-signed.hap) SIGNED=1 ;;
esac

# Ship it back into the worktree for inspection. cangjie/harmony/out/.gitignore keeps it untracked.
OUT_DIR="$CJ_ROOT/harmony/out"
mkdir -p "$OUT_DIR"
cp -f "$HAP" "$OUT_DIR/"
OUT_HAP="$OUT_DIR/$(basename "$HAP")"

log "HAP: $OUT_HAP"
log "     $(stat -c%s "$HAP") bytes ($(du -h "$HAP" | cut -f1)), product=$PRODUCT, $SIGNING_NOTE"
log "sha256: $(sha256sum "$HAP" | cut -d' ' -f1)"

# One listing, read many times: the per-entry assertions below must not stream the archive into a
# short-circuiting grep (see the note at the `for required` loop).
HAP_LISTING="$(mktemp)"
trap 'rm -f "$HAP_LISTING"' EXIT
unzip -l "$HAP" >"$HAP_LISTING"

log "native payload inside the HAP:"
awk '$4 ~ /libs\/arm64-v8a\/.*\.so$/ {printf "    %10s  %s\n", $1, $4}' "$HAP_LISTING" | sort -k2
TOPLEVEL_COUNT="$(awk '$4 ~ /^libs\/arm64-v8a\/[^/]+\.so$/ {n++} END {print n+0}' "$HAP_LISTING")"
log "    $TOPLEVEL_COUNT libraries in libs/arm64-v8a/"
log "interop runtime inside the HAP:"
awk '$4 ~ /libs\/arm64-v8a\/ohos\/.*\.so$/ {printf "    %10s  %s\n", $1, $4}' "$HAP_LISTING" | sort -k2
OHOS_COUNT="$(awk '$4 ~ /libs\/arm64-v8a\/ohos\/.*\.so$/ {n++} END {print n+0}' "$HAP_LISTING")"
log "    $OHOS_COUNT libraries in libs/arm64-v8a/ohos/"
log "bundleName: $BUNDLE"

for required in libs/arm64-v8a/libmain.so libs/arm64-v8a/libtextura_host.so \
                libs/arm64-v8a/libSDL3.so libs/arm64-v8a/libSDL3_ttf.so \
                libs/arm64-v8a/libcangjie-runtime.so libs/arm64-v8a/libark_interop_loader.so \
                libs/arm64-v8a/ohos/libohos.ark_interop.so \
                libs/arm64-v8a/ohos/libohos_ark_interop_diff.z.so; do
  # `unzip -l "$HAP" | grep -q` is not usable here: grep -q exits at the first match, unzip then dies
  # of SIGPIPE, and pipefail turns that into a failed pipeline — so an *early* entry in the archive
  # (libSDL3.so, libSDL3_ttf.so) reported as missing while a late one passed. grep the captured
  # listing instead.
  if ! grep -q " $required\$" "$HAP_LISTING"; then
    die "HAP is missing $required"
  fi
done
[ "$OHOS_COUNT" -ge "${#OHOS_INTEROP_LIBS[@]}" ] || \
  die "libs/arm64-v8a/ohos/ holds $OHOS_COUNT libraries, expected at least ${#OHOS_INTEROP_LIBS[@]} — the loader cannot start the Cangjie runtime without them"
log "required payload present: libmain.so, libtextura_host.so, libSDL3.so, libSDL3_ttf.so,"
log "                           libcangjie-runtime.so, libark_interop_loader.so, ohos/ interop runtime"

# Re-run this at any time to audit the artifact:
cat <<EOF

Verify the payload of this HAP yourself:

  unzip -l "$OUT_HAP" | awk '\$4 ~ /libs\\/arm64-v8a\\/[^/]+\\.so\$/ {n++} END {print n" top-level libs"}'
  unzip -l "$OUT_HAP" | awk '\$4 ~ /libs\\/arm64-v8a\\/ohos\\/[^/]+\\.so\$/ {print \$4}'
EOF

if [ "$SIGNED" != 1 ]; then
  cat <<EOF

STATUS: NOT INSTALLABLE. $(basename "$OUT_HAP") is unsigned.

  A HarmonyOS device only installs HAPs signed with a debug profile issued for
  bundleName=$BUNDLE and bound to that device's UDID. There is no offline self-signing
  path: the profile signature chains to the AGC root, so the profile must come from
  AGC (DevEco Studio / devecocli, both need a Huawei developer login) — see
  cangjie/docs/HARMONY.md §7.1.

  To install: supply the material and re-run this script.

    cangjie/scripts/harmony/set_signing_material.sh \\
      --store-file <store.p12> --key-alias <alias> --cert <cert.cer> --profile <profile.p7b> \\
      [--store-password <enc>] [--key-password <enc>]

  Expected: this script then reports "STATUS: installable".
EOF
else
  cat <<EOF

STATUS: installable, provided (a) the issuing debug profile lists this device's UDID and
        (b) the device firmware ships the Cangjie interop system libraries.
        (a) cannot be checked from here; (b) is check 1 below — run it first.

Device-side acceptance sequence (hdc is not on PATH, so the absolute path is required):

  # 1) the device must provide these itself; they cannot be put in a HAP
  $HDC shell 'ls /system/lib64/platformsdk/ | grep -E "ark_interop|cj_environment"'
     expected: libark_interop.z.so, libcj_environment.z.so
     missing => the Cangjie runtime cannot start on this firmware; stop here

  # 2) install
  $HDC install -r "$OUT_HAP"

  # 3) start
  $HDC shell aa start -a EntryAbility -b $BUNDLE

  # 4) host log (the hilog tag is "Textura/HOST"/"Textura/FOCUS", so \`hilog -T Textura\` matches nothing)
  $HDC shell hilog | grep -E 'Textura/(HOST|FOCUS)'

See cangjie/docs/HARMONY.md §6 for the expected log lines and the most likely failure points.
EOF
fi
