#!/usr/bin/env bash
# On-device stability soak (docs/STABILITY.md §3).
#
# Drives the app the way a person does — the seven sidebar routes, the quick-capture overlay in and
# out, wheel scrolling in the content area — for a fixed number of seconds, while sampling
# `pidof com.ethancheung.textura` the whole time and watching the probe's failure counter in
# `<sandbox>/diag.log`. Two things are asserted:
#
#   1. the process is alive at every sample (a died process is what the user reports as 闪退);
#   2. no `fail n=` line appeared (a frame that throws every frame looks alive but stops taking
#      input — the "静默冻结" of docs/DEVICE-NOTES.md §9).
#
# The `fail` counter needs a diagnostic build (`TEXTURA_PROBE=1 scripts/harmony/build_ohos.sh`),
# because the probe is compiled out of shipping builds. Without it this script still proves (1).
#
# Usage: scripts/harmony/device_stability.sh [seconds]   # default 180
#        HDC_TARGET=192.168.0.3:36773 scripts/harmony/device_stability.sh 60
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

DURATION="${1:-180}"
BUNDLE="com.ethancheung.textura"
SANDBOX="/data/app/el2/100/base/$BUNDLE/files/textura"
DIAG="$SANDBOX/diag.log"

command -v "$HDC" >/dev/null || die "hdc not found at $HDC"
TARGET="${HDC_TARGET:-$("$HDC" list targets | sed -n '1p' | tr -d '\r')}"
[ -n "$TARGET" ] || die "no device: hdc list targets is empty"
hdc_() { "$HDC" -t "$TARGET" shell "$@"; }

# Sidebar entries, screen coordinates. The window origin is (614,177) and the content origin is
# (614,242) on this MateBook (docs/DEVICE-NOTES.md §7/§9.4); these are the x=674 column.
ROUTE_CLICKS=(
  "dashboard 674 331"
  "calendar 674 367"
  "gtd 674 440"
  "okr 674 404"
  "gantt 674 477"
  "sop 674 513"
  "settings 674 549"
)
# Quick capture lives in the GTD top bar; the overlay is closed with Escape (KEYCODE_ESCAPE 2070).
CAPTURE_CLICK=(1234 292)

pid() { hdc_ "pidof $BUNDLE" 2>/dev/null | tr -d '\r'; }
taps() { hdc_ "uitest uiInput click $1 $2" >/dev/null 2>&1 || true; }

log "target=$TARGET duration=${DURATION}s"
first_pid="$(pid)"
[ -n "$first_pid" ] || die "app is not running: start it with aa start -a EntryAbility -b $BUNDLE"
log "app pid=$first_pid"

fail_before=0
if hdc_ "test -r $DIAG && echo yes" | grep -q yes; then
  fail_before="$(hdc_ "grep -c 'fail n=' $DIAG" 2>/dev/null | tr -d '\r')"
  log "diagnostic build detected: diag.log readable, fail lines before=$fail_before"
else
  log "no readable diag.log (shipping build): only the process-alive half of the gate runs"
fi

deadline=$(( $(date +%s) + DURATION ))
samples=0
deaths=0
rounds=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  rounds=$((rounds + 1))
  for entry in "${ROUTE_CLICKS[@]}"; do
    read -r name x y <<<"$entry"
    taps "$x" "$y"
    samples=$((samples + 1))
    if [ -z "$(pid)" ]; then
      deaths=$((deaths + 1))
      log "DEATH after clicking $name (round $rounds)"
      break 2
    fi
    # The SOP route is the expensive one (full auto-layout); give it the wheel too.
    [ "$name" = "sop" ] && { hdc_ "uinput -M -s -4" >/dev/null 2>&1 || true; }
  done
  # Overlay round trip: open quick capture, close with Escape.
  taps "${CAPTURE_CLICK[0]}" "${CAPTURE_CLICK[1]}"
  hdc_ "uitest uiInput keyEvent 2070" >/dev/null 2>&1 || true
  samples=$((samples + 1))
  if [ -z "$(pid)" ]; then
    deaths=$((deaths + 1))
    log "DEATH after the quick-capture round trip (round $rounds)"
    break
  fi
done

last_pid="$(pid)"
log "rounds=$rounds pid_samples=$samples deaths=$deaths"
if [ -n "$last_pid" ]; then
  log "app still alive: pid=$last_pid"
else
  log "STATUS: FAIL — the process disappeared"
  exit 1
fi

if hdc_ "test -r $DIAG && echo yes" | grep -q yes; then
  fail_after="$(hdc_ "grep -c 'fail n=' $DIAG" 2>/dev/null | tr -d '\r')"
  delta=$(( fail_after - fail_before ))
  log "fail lines after=$fail_after delta=$delta"
  if [ "$delta" -ne 0 ]; then
    hdc_ "grep -n 'fail n=' $DIAG | tail -5"
    log "STATUS: FAIL — $delta frame failures during the soak"
    exit 1
  fi
  log "STATUS: PASS (alive throughout, fail=0)"
else
  log "STATUS: PASS (alive throughout; fail counter not instrumented in this build)"
fi
