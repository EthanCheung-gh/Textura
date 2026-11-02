#!/usr/bin/env bash
# Shared helpers for the HarmonyOS scripts. Source it; do not execute it.
#
# Every HarmonyOS build runs inside a snapshot copy of the repository, never in the shared worktree:
# cjpm and hvigor write target/, .hvigor/, oh_modules/ and build/ directories that would collide with
# the desktop build and with other workers. Snapshot layout mirrors the repository root so the hvigor
# project (cangjie/harmony) finds its own root.
#
# Overridable:
#   TEXTURA_CANGJIE_ROOT   cangjie/ directory of the source tree (default: this script's ../..)
#   TEXTURA_HARMONY_SNAP   snapshot directory          (default: /tmp/cj-harmony)
#   DEVECO_HOME            command-line-tools root     (default: ~/deveco-cli-stable/command-line-tools)
#   CJ_HOME                cjv home                    (default: ~/.cjv)
#   TEXTURA_OHOS_SDK       HarmonyOS Cangjie SDK root  (default: ~/cangjie-ohos-sdk, holds cangjie/)
#   TEXTURA_OHOS_LIBCXX    aarch64-ohos libc++.so with the std::__h ABI (see stage_libs.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CJ_ROOT="${TEXTURA_CANGJIE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REPO_ROOT="$(cd "$CJ_ROOT/.." && pwd)"
SNAP="${TEXTURA_HARMONY_SNAP:-/tmp/cj-harmony}"
CLT="${DEVECO_HOME:-$HOME/deveco-cli-stable/command-line-tools}"
CJ_HOME_DIR="${CJ_HOME:-$HOME/.cjv}"
OHOS_SDK="${TEXTURA_OHOS_SDK:-$HOME/cangjie-ohos-sdk}"

HARMONY_REL="cangjie/harmony"
SNAP_CJ="$SNAP/cangjie"
SNAP_HARMONY="$SNAP/$HARMONY_REL"
HOST_PKG="$SNAP_HARMONY/host"
LIBS_DIR="$SNAP_HARMONY/entry/libs/arm64-v8a"
OHOS_LIBS_DIR="$LIBS_DIR/ohos"
# Device-extracted libraries (libc++ and friends) live in the worktree, not in the snapshot: the
# snapshot is rsync --delete'd on every build, and these files must never be committed (see
# cangjie/.gitignore). Point TEXTURA_OHOS_LIBCXX anywhere to override.
DEVICE_LIBS="$CJ_ROOT/harmony/device-libs"

OHOS_TOOLCHAIN="$CJ_HOME_DIR/toolchains/sts-1.2.0-linux-x64-ohos"
OHOS_RUNTIME_LIB="$OHOS_TOOLCHAIN/runtime/lib/linux_ohos_aarch64_cjnative"
# The HarmonyOS Cangjie SDK lays its payload out in two places: the module libraries (`libohos.*.so`,
# `libcj_ndk_ffi.z.so`) next to the `.cjo` of every `ohos.*` package, and the C-wrapper diff shims
# (`libohos_*_diff.z.so`) in c_wrapper_diff. Both end up in the HAP's libs/arm64-v8a/ohos/ subdir.
OHOS_SDK_OHOS_LIBS="$OHOS_SDK/cangjie/build/linux_ohos_aarch64_llvm/ohos"
OHOS_SDK_DIFF_LIBS="$OHOS_SDK/cangjie/c_wrapper_diff/linux_ohos_aarch64_llvm"
OHOS_SDK_RUNTIME_LIBS="$OHOS_SDK/cangjie/compiler/runtime/lib/linux_ohos_aarch64_llvm"
NATIVE_SYSROOT="$CLT/sdk/default/openharmony/native/sysroot"
OHOS_SYSLIB="$NATIVE_SYSROOT/usr/lib/aarch64-linux-ohos"
READELF="$CLT/sdk/default/openharmony/native/llvm/bin/llvm-readelf"
HVIGORW="$CLT/bin/hvigorw"
# hdc ships inside the command-line tools and is not on PATH on this machine, so every printed
# device command uses the absolute path.
HDC="$CLT/sdk/default/openharmony/toolchains/hdc"
# Interop runtime the loader resolves at run time, in the layout the loader hard-codes
# (`.../libs/arm64-v8a/ohos`). The set matches a HAP that is known to run on a real device
# (PixCap-Cangjie, build ids identical to the SDK files staged here); see docs/HARMONY.md §5.4.
OHOS_INTEROP_LIBS=(
  libohos.ark_interop.so
  libohos.ark_interop_helper.so
  libohos.ffi.so
  libohos.so
  libohos.base.so
  libohos.ability.so
  libcj_ndk_ffi.z.so
  libohos_ark_interop_diff.z.so
)

# A soname is "platform-provided" when the HarmonyOS native sysroot ships it: the sysroot is the
# public NDK surface, so those libraries are present in the device's own /system/lib64 and must not
# be shipped inside the HAP. This is decided by inspection, not by a hand-written allowlist, so a
# newly added SDL/OHOS dependency shows up as a real question instead of a silent omission.
#
# The single exception is libc++.so: the sysroot does not carry it (see stage_libs.sh).
platform_provided() {
  [ -f "$OHOS_SYSLIB/$1" ]
}

log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# cjc/LLVM put their intermediate objects in $TMPDIR (default /tmp) and hvigor writes its HAP archive
# next to the snapshot. On a machine where /tmp is a small tmpfs shared with other jobs both fail with
# "Detail: IO failure on output stream: Disk quota exceeded" / "PackageHap ... Disk quota exceeded",
# which reads like a source error and is easy to misdiagnose. Warn early instead.
require_tmp_space() {
  local dir="${TMPDIR:-/tmp}" avail_kb=""
  avail_kb="$(df -Pk "$dir" 2>/dev/null | awk 'NR==2 {print $4}')" || return 0
  [ -n "$avail_kb" ] || return 0
  if [ "$avail_kb" -lt 2097152 ]; then
    warn "$dir has $((avail_kb / 1024)) MB free; a cjc+hvigor run needs roughly 2 GB of scratch space."
    warn "  point it at a roomier filesystem before retrying, e.g.:"
    warn "    export TMPDIR=\$HOME/.cache/tmp && mkdir -p \"\$TMPDIR\""
  fi
}

require_file() {
  [ -e "$1" ] || die "missing $1${2:+ ($2)}"
}

is_aarch64() {
  case "$(file -b "$1" 2>/dev/null)" in
    *aarch64*) return 0 ;;
    *) return 1 ;;
  esac
}

# Refresh the snapshot from the shared worktree. --delete keeps it honest: a file removed upstream
# must not survive in the snapshot and silently change the build.
sync_snapshot() {
  log "snapshot $REPO_ROOT -> $SNAP"
  mkdir -p "$SNAP"
  rsync -a --delete \
    --exclude target \
    --exclude 'tools/parity/out' \
    --exclude 'harmony/out' \
    --exclude node_modules \
    --exclude dist \
    "$REPO_ROOT/" "$SNAP/"
}

# Put the aarch64-linux-ohos SDL3 libraries where the Cangjie bindings look for them
# (third_party/cangjie-sdl/.sdl3). Idempotent: host x86_64 copies are parked in .sdl3.host, and the
# ohos copies are re-staged on every run.
stage_ohos_sdl_bindings() {
  local sdl_dir="$SNAP_CJ/third_party/cangjie-sdl"
  require_file "$sdl_dir/.sdl3-ohos/libSDL3.so" "vendored aarch64-linux-ohos SDL3"
  mkdir -p "$sdl_dir/.sdl3" "$sdl_dir/.sdl3.host"
  local f
  for f in "$sdl_dir/.sdl3"/*.so; do
    [ -e "$f" ] || continue
    if ! is_aarch64 "$f"; then
      mv -f "$f" "$sdl_dir/.sdl3.host/"
    fi
  done
  cp -f "$sdl_dir/.sdl3-ohos/libSDL3.so" "$sdl_dir/.sdl3-ohos/libSDL3_ttf.so" "$sdl_dir/.sdl3/"
  log "SDL bindings root: $(file -b "$sdl_dir/.sdl3/libSDL3.so" | cut -d, -f2)"
}

# cjpm emits a bare `crti.o`/`crtn.o` on the final ld.lld command line, and ld.lld resolves a bare
# file name against the *current directory* only (-L/--sysroot apply to -l lookups). The link runs
# with the module directory as its working directory, so the two crt objects have to exist there.
# This is a build-tree-only shim: cangjie/harmony/host/ carries no crt files in the repository.
provide_crt_objects() {
  require_file "$OHOS_SYSLIB/crti.o" "HarmonyOS native sysroot"
  ln -sf "$OHOS_SYSLIB/crti.o" "$HOST_PKG/crti.o"
  ln -sf "$OHOS_SYSLIB/crtn.o" "$HOST_PKG/crtn.o"
}

# cjpm.toml cannot expand environment variables, so the repository version of
# cangjie/harmony/host/cjpm.toml carries the token __OHOS_SYSROOT__ and every build stamps the real
# sysroot path into the *snapshot* copy. A moved command-line-tools install, a different machine or a
# second SDK therefore never silently links against a stale absolute path.
stamp_host_sysroot() {
  local toml="$HOST_PKG/cjpm.toml"
  require_file "$toml" "harmony host package missing from the snapshot"
  require_file "$OHOS_SYSLIB/libc.so" "HarmonyOS native sysroot (DEVECO_HOME=$CLT)"
  sed -i.bak "s|__OHOS_SYSROOT__|$NATIVE_SYSROOT|g" "$toml"
  rm -f "$toml.bak"
  if grep -q '__OHOS_SYSROOT__' "$toml"; then
    die "could not stamp the HarmonyOS sysroot into $toml"
  fi
  log "host link sysroot: $NATIVE_SYSROOT"
}

# Debug provisioning profiles (.p7b) are PKCS#7 blobs whose JSON payload carries the bundleName and
# the authorized device UDIDs in clear text. hvigor only reports a mismatch *after* a long build
# (00303074), so the scripts read the payload up front and compare it with AppScope/app.json5.
profile_bundle_name() {
  [ -f "${1:-}" ] || return 1
  strings "$1" | grep -o '"bundle-name":"[^"]*"' | head -1 | sed 's/.*:"//; s/"$//'
}

profile_device_ids() {
  [ -f "${1:-}" ] || return 1
  strings "$1" | grep -o '"device-ids":\[[^]]*\]' | head -1 | tr -d '"' | sed 's/device-ids:\[//; s/\]$//'
}

app_bundle_name() {
  local app="$SNAP_HARMONY/AppScope/app.json5"
  [ -f "$app" ] || app="$CJ_ROOT/harmony/AppScope/app.json5"
  sed -n 's/.*"bundleName": *"\([^"]*\)".*/\1/p' "$app" 2>/dev/null | head -1
}

ohos_env() {
  [ -x "$CJ_HOME_DIR/bin/cjv" ] || die "cjv not found at $CJ_HOME_DIR/bin/cjv"
  if [ ! -d "$OHOS_TOOLCHAIN" ]; then
    log "installing the ohos cross target (cjv install sts-1.2.0 -t ohos)"
    "$CJ_HOME_DIR/bin/cjv" install sts-1.2.0 -t ohos
  fi
  # The sanctioned way to reach the target variant: cjv refuses to make it the active toolchain.
  eval "$("$CJ_HOME_DIR/bin/cjv" envsetup sts-1.2.0 --target ohos)"
}
