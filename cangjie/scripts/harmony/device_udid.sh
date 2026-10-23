#!/usr/bin/env bash
# Print the UDID of the connected HarmonyOS device. AGC needs it to authorize a debug profile.
#
# hdc is not on PATH on this machine, so the absolute path from the command-line tools is used.
# USB devices show up automatically; a wireless device must be connected first:
#   <hdc> tconn <ip>:<port>
#
# Usage:
#   cangjie/scripts/harmony/device_udid.sh [-t <connect-key>] [-h|--help]
#
#   -t, --target <key>   pick one entry from `hdc list targets` (needed when several are attached)
#
# Exit status: 0 with the UDID on stdout, 1 when no device is reachable or the UDID cannot be read.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

TARGET=""

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -t|--target) TARGET="${2:-}"; shift 2 ;;
    -h|--help)   usage 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

require_file "$HDC" "hdc from the DevEco command-line tools (set DEVECO_HOME to override)"
[ -x "$HDC" ] || die "$HDC is not executable"

# hdc exits 0 even when it cannot talk to a device, so both stdout and stderr are inspected.
list_targets() {
  "$HDC" list targets 2>&1 | tr -d '\r' \
    | grep -v '^\[Empty\]$' \
    | grep -v '^Empty$' \
    | grep -v '^$' \
    | grep -v '^\[Info\]' \
    | grep -v '^\[Fail\]' || true
}

TARGETS="$(list_targets)"

if [ -n "$TARGET" ]; then
  printf '%s\n' "$TARGETS" | grep -Fxq "$TARGET" \
    || die "device '$TARGET' is not in 'hdc list targets':
$(printf '%s\n' "$TARGETS" | sed 's/^/  /')"
elif [ -z "$TARGETS" ]; then
  warn "no HarmonyOS device is connected (hdc list targets: [Empty])"
  cat >&2 <<EOF

Connect the device first, then re-run this script:
  USB   : enable Developer options > USB debugging, plug it in, accept the authorization dialog
  TCP   : $HDC tconn <ip>:<port>        # wireless debugging, port from the device's screen
  check : $HDC list targets

No hdc at all? The DevEco Studio Device Manager shows the UDID as well.
EOF
  exit 1
fi

# More than one target is ambiguous: print them and ask for -t instead of silently picking one.
if [ -z "$TARGET" ]; then
  COUNT="$(printf '%s\n' "$TARGETS" | grep -c . || true)"
  if [ "$COUNT" -gt 1 ]; then
    warn "more than one device is connected; pick one with -t <connect-key>:"
    printf '%s\n' "$TARGETS" | sed 's/^/  /' >&2
    exit 1
  fi
  TARGET="$(printf '%s\n' "$TARGETS" | head -1)"
fi

hdc_shell() {
  if [ -n "$TARGET" ]; then
    "$HDC" -t "$TARGET" shell "$@" 2>&1
  else
    "$HDC" shell "$@" 2>&1
  fi
}

# `bm get -u` output differs between HarmonyOS generations:
#   udid of current device is :
#   <64 hex chars>
#   {"udid":"<...>"}
#   <64 hex chars>
# so accept all of them and reject everything that is not a plausible UDID token.
extract_udid() {
  local raw="$1" value=""
  raw="$(printf '%s\n' "$raw" | tr -d '\r')"

  value="$(printf '%s\n' "$raw" \
    | sed -n 's/.*"udid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"

  if [ -z "$value" ]; then
    value="$(printf '%s\n' "$raw" \
      | sed -n 's/.*[Uu][Dd][Ii][Dd][^:]*:[[:space:]]*\([0-9A-Za-z._:-]\{16,\}\).*/\1/p' | head -1)"
  fi

  if [ -z "$value" ]; then
    value="$(printf '%s\n' "$raw" \
      | awk '/[Uu][Dd][Ii][Dd].*:[[:space:]]*$/ { getline; print; exit }')"
  fi

  if [ -z "$value" ]; then
    value="$(printf '%s\n' "$raw" | grep -oE '[0-9A-Za-z]{16,}' | tail -1 || true)"
  fi

  value="$(printf '%s' "$value" | tr -d "[:space:]\"'")"
  case "$value" in
    *[Ff]ail*|*connect-key*|*[Ee]rror*) return 1 ;;
  esac
  [ "${#value}" -ge 16 ] || return 1
  printf '%s\n' "$value"
}

RAW="$(hdc_shell bm get -u || true)"
UDID="$(extract_udid "$RAW" || true)"

if [ -z "$UDID" ]; then
  RAW="$(hdc_shell bm get --udid || true)"
  UDID="$(extract_udid "$RAW" || true)"
fi

if [ -z "$UDID" ]; then
  warn "device '$TARGET' is connected, but its UDID could not be read"
  warn "raw output of 'bm get -u':"
  printf '%s\n' "$RAW" | sed 's/^/    /' >&2
  warn "try: $HDC -t $TARGET shell bm get --udid"
  warn "or read the UDID in DevEco Studio > Device Manager"
  exit 1
fi

printf 'device : %s\n' "$TARGET"
printf 'UDID   : %s\n' "$UDID"
printf '\nRegister this UDID in AppGallery Connect > Devices, then issue the debug profile (.p7b)\n'
printf 'for bundleName com.ethancheung.textura; a profile that does not list this UDID cannot install.\n'
