#!/usr/bin/env bash
# Stage every native library the HAP needs into cangjie/harmony/entry/libs/arm64-v8a of the snapshot.
#
# The payload is the union of two things, and nothing else:
#
#   A. NEEDED closure of libtextura_host.so and libSDL3.so over the ohos toolchain runtime, minus the
#      sonames the device platform provides (present in the HarmonyOS native sysroot). This is the
#      difference from the reference project's 60-library payload — unused Cangjie std packages
#      (unittest, database, net, ...) stay out.
#   B. libraries the runtime opens *by name* at run time, which no NEEDED entry can express:
#        - libark_interop_loader.so     ArkTS-side loader, dlopen'd by requireCJLib()
#        - ohos/*.so                    interop runtime the loader resolves after starting the
#                                       Cangjie runtime (loader hard-codes .../libs/arm64-v8a/ohos)
#        - libsecurec.so                NEEDED of every bundled libohos.*.so
#      Set B is not optional: an HAP without libs/arm64-v8a/ohos/ builds fine and fails on device.
#
# Sources, in resolution order, for the closure:
#   1. the freshly cross-built host library
#   2. third_party/cangjie-sdl/.sdl3-ohos                (SDL3, SDL3_ttf)
#   3. $OHOS_TOOLCHAIN/runtime/lib/linux_ohos_aarch64_cjnative  (libcangjie-*, libboundscheck)
#   4. libc++.so  — NOT in any toolchain on this machine; see below
#   5. $OHOS_SDK (DevEco Cangjie SDK): loader, libohos.*, c_wrapper_diff shims, libsecurec.so
#
# libc++: libcangjie-runtime.so has `NEEDED libc++.so`, and the runtime was built against the
# LLVM libc++ that exports the `std::__h` namespace (e.g. _ZNSt3__h15recursive_mutex4lockEv). The
# DevEco SDK's BiSheng copies export `std::__n1` instead and cannot satisfy it. Resolution order:
#   $TEXTURA_OHOS_LIBCXX
#   cangjie/harmony/device-libs/arm64-v8a/libc++.so      (git-ignored drop dir, see below)
#   PixCap-Cangjie/entry/libs/arm64-v8a/libc++.so        (read-only reference copy)
# The file is a device library: pull it with (hdc is not on PATH, use the absolute path)
#   ~/deveco-cli-stable/command-line-tools/sdk/default/openharmony/toolchains/hdc \
#     file recv /system/lib64/libc++.so cangjie/harmony/device-libs/arm64-v8a/libc++.so
# and never commit it (cangjie/.gitignore keeps harmony/device-libs/ out). Shipping a
# device-extracted system library still needs a licensing review; see docs/HARMONY.md §7.2.
#
# Known risk R5: libcangjie-runtime.so calls dlopen("libcangjie-trace.so") by name (the string is in
# its .rodata, next to the `%s/runtime/lib/%s_cjnative/libcangjie-trace.so` fallback pattern) and no
# toolchain on this machine ships that library. It is a debug/tracing aid: an absent library only
# prints a dlopen failure. Verify on device as documented in docs/HARMONY.md §7.4.
#
# Usage: cangjie/scripts/harmony/stage_libs.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

HOST_SO="$HOST_PKG/target/aarch64-linux-ohos/release/textura_host/libtextura_host.so"
require_file "$HOST_SO" "run build_ohos.sh first"
require_file "$OHOS_SDK_OHOS_LIBS/libark_interop_loader.so" "HarmonyOS Cangjie SDK (TEXTURA_OHOS_SDK)"

mkdir -p "$LIBS_DIR"
log "staging into $LIBS_DIR"

# ------------------------------------------------------------------ closed set of needed sonames
# Breadth-first over NEEDED. A soname is resolved against the candidate directories, and the walk
# continues from whatever was resolved, so transitive dependencies are covered without shipping
# unrelated libraries.
declare -A RESOLVED=()
declare -a QUEUE=()
declare -A VISITED=()

resolve_soname() {
  local name="$1" dir
  for dir in "$(dirname "$HOST_SO")" "$SNAP_CJ/third_party/cangjie-sdl/.sdl3-ohos" "$OHOS_RUNTIME_LIB"; do
    if [ -f "$dir/$name" ]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

enqueue() {
  local soname
  while read -r soname; do
    [ -n "$soname" ] || continue
    platform_provided "$soname" && continue
    [ "$soname" = "libc++.so" ] && continue # handled explicitly below
    [ -n "${VISITED[$soname]:-}" ] && continue
    VISITED[$soname]=1
    QUEUE+=("$soname")
  done < <("$READELF" -d "$1" | awk '/NEEDED/ {gsub(/[][]/,"",$5); print $5}')
}

enqueue "$HOST_SO"

index=0
while [ "$index" -lt "${#QUEUE[@]}" ]; do
  soname="${QUEUE[$index]}"
  index=$((index + 1))
  if path="$(resolve_soname "$soname")"; then
    RESOLVED["$soname"]="$path"
    enqueue "$path"
  else
    warn "unresolved soname: $soname — present neither in the ohos toolchain, the vendored SDL root,"
    warn "  nor the HarmonyOS native sysroot; the app will fail to load it on device"
  fi
done

for soname in "${!RESOLVED[@]}"; do
  cp -f "${RESOLVED[$soname]}" "$LIBS_DIR/$soname"
done

# ------------------------------------------------------------------------------ libc++ (special)
LIBCXX_DEST="$LIBS_DIR/libc++.so"
LIBCXX_CANDIDATES=(
  "${TEXTURA_OHOS_LIBCXX:-}"
  "$DEVICE_LIBS/arm64-v8a/libc++.so"
  "$REPO_ROOT/../PixCap-Cangjie/entry/libs/arm64-v8a/libc++.so"
)
LIBCXX_SYMBOL='_ZNSt3__h15recursive_mutex4lockEv'

# `readelf | grep -q` would close the pipe early and fail under `set -o pipefail`, so probe with a
# temp file instead.
has_std_h_abi() {
  local tmp
  tmp="$(mktemp)"
  "$READELF" --dyn-syms "$1" >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  grep -q "$LIBCXX_SYMBOL" "$tmp"
  local found=$?
  rm -f "$tmp"
  return $found
}

if [ -f "$LIBCXX_DEST" ] && has_std_h_abi "$LIBCXX_DEST"; then
  log "libc++.so already staged with the std::__h ABI"
else
  for candidate in "${LIBCXX_CANDIDATES[@]}"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ] && has_std_h_abi "$candidate"; then
      cp -f "$candidate" "$LIBCXX_DEST"
      log "libc++.so staged from $candidate (device-extracted, see the header comment)"
      break
    fi
  done
fi
if [ ! -f "$LIBCXX_DEST" ] || ! has_std_h_abi "$LIBCXX_DEST"; then
  warn "no libc++.so with the std::__h ABI available."
  warn "  pull it from a device:"
  warn "  $HDC file recv /system/lib64/libc++.so cangjie/harmony/device-libs/arm64-v8a/libc++.so"
  warn "  or set TEXTURA_OHOS_LIBCXX=<path>. The HAP still builds, but the process will fail to"
  warn "  load libcangjie-runtime.so on device."
fi

# ------------------------------------------------------------------------- loader + host library
cp -f "$HOST_SO" "$LIBS_DIR/libtextura_host.so"
cp -f "$OHOS_SDK_OHOS_LIBS/libark_interop_loader.so" "$LIBS_DIR/libark_interop_loader.so"

# ------------------------------------------------------- interop runtime, resolved by name (set B)
# The loader looks for these in <lib dir>/ohos after it has started the Cangjie runtime, so a missing
# directory is invisible at build time and fatal on device. Rebuilt from scratch every run: a library
# removed from OHOS_INTEROP_LIBS must not survive from an older build.
rm -rf "$OHOS_LIBS_DIR"
mkdir -p "$OHOS_LIBS_DIR"
for name in "${OHOS_INTEROP_LIBS[@]}"; do
  src=""
  for dir in "$OHOS_SDK_OHOS_LIBS" "$OHOS_SDK_DIFF_LIBS"; do
    if [ -f "$dir/$name" ]; then
      src="$dir/$name"
      break
    fi
  done
  [ -n "$src" ] || die "missing $name in the HarmonyOS Cangjie SDK ($OHOS_SDK); the loader cannot start the runtime without it"
  cp -f "$src" "$OHOS_LIBS_DIR/$name"
done
log "interop runtime: ${#OHOS_INTEROP_LIBS[@]} libraries in $OHOS_LIBS_DIR"

# libsecurec.so is NEEDED by every bundled libohos.*.so and is NOT in the HarmonyOS native sysroot,
# so the device cannot provide it. Take the SDK's own copy (same release as the interop libraries);
# fall back to the cjv runtime's libboundscheck.so binary, which is the same library under the name
# the reference project shipped.
SECUREC_DEST="$LIBS_DIR/libsecurec.so"
if [ ! -f "$SECUREC_DEST" ]; then
  if [ -f "$OHOS_SDK_RUNTIME_LIBS/libsecurec.so" ]; then
    cp -f "$OHOS_SDK_RUNTIME_LIBS/libsecurec.so" "$SECUREC_DEST"
    log "libsecurec.so staged from $OHOS_SDK_RUNTIME_LIBS"
  elif [ -f "$OHOS_RUNTIME_LIB/libboundscheck.so" ]; then
    cp -f "$OHOS_RUNTIME_LIB/libboundscheck.so" "$SECUREC_DEST"
    warn "libsecurec.so staged as a copy of the cjv runtime's libboundscheck.so (same library, the"
    warn "  reference project shipped it under this name); the DevEco SDK copy was not found"
  else
    warn "libsecurec.so missing: libohos.*.so will fail to load, interop stays dead on device"
  fi
fi

# libmain.so is produced by CMake inside the hvigor build; an old copy from a previous snapshot is
# dropped so a stale shim can never be shipped by accident.
rm -f "$LIBS_DIR/libmain.so"

# ----------------------------------------------------------------------------------- verification
log "staged libraries:"
staged=0
for f in "$LIBS_DIR"/*.so; do
  [ -e "$f" ] || continue
  is_aarch64 "$f" || die "$(basename "$f") is not aarch64: $(file -b "$f")"
  staged=$((staged + 1))
done
[ "$staged" -gt 0 ] || die "nothing staged"
printf '    %3d libraries, %s total\n' "$staged" "$(du -sh "$LIBS_DIR" | cut -f1)"
ls -1 "$LIBS_DIR" | sed 's/^/    /'

interop=0
for f in "$OHOS_LIBS_DIR"/*.so; do
  [ -e "$f" ] || continue
  is_aarch64 "$f" || die "ohos/$(basename "$f") is not aarch64: $(file -b "$f")"
  interop=$((interop + 1))
done
[ "$interop" -eq "${#OHOS_INTEROP_LIBS[@]}" ] || die "ohos/ holds $interop libraries, expected ${#OHOS_INTEROP_LIBS[@]}"
printf '    %3d interop libraries in ohos/:\n' "$interop"
ls -1 "$OHOS_LIBS_DIR" | sed 's/^/    /'

# Interop NEEDED entries that are neither bundled nor in the sysroot: those names are resolved from
# the device's own platformsdk directory (proved on device by the reference HAP). Listed, not fatal,
# because the sysroot is only the public NDK surface and does not enumerate the Cangjie bridges.
log "interop NEEDED entries assumed to come from the device platform (not bundled):"
for f in "$OHOS_LIBS_DIR"/*.so; do
  [ -e "$f" ] || continue
  "$READELF" -d "$f" | awk '/NEEDED/ {gsub(/[][]/,"",$5); print $5}'
done | sort -u | while read -r soname; do
  [ -f "$OHOS_LIBS_DIR/$soname" ] && continue
  [ -f "$LIBS_DIR/$soname" ] && continue
  platform_provided "$soname" && continue
  printf '    %s\n' "$soname"
done

log "unresolved (device-provided) sonames are listed above; every bundled NEEDED soname is present"
log "in $LIBS_DIR, and the ohos/ interop runtime is staged"
log "done — next: cangjie/scripts/harmony/assemble_hap.sh"
