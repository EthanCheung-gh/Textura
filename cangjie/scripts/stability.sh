#!/usr/bin/env bash
# Host stability gate — see docs/STABILITY.md.
#
# Why this exists: a red assertion is easy to read, but the failure the user actually hits is a
# *process death*. A SIGSEGV/SIGABRT kills the test binary and takes every remaining case with it, and
# on the device the same defect is just "the app disappeared". Both are invisible in a single run, so
# the gate runs the same suites many times and counts deaths instead of relying on one green pass.
#
#   scripts/stability.sh                          # 50 runs per suite (the gate)
#   TEXTURA_STRESS_RUNS=5 scripts/stability.sh    # quick smoke while iterating
#   TEXTURA_STRESS_SUITES="textura.shell" scripts/stability.sh
#   TEXTURA_STABILITY_TARGET_DIR=/path/target scripts/stability.sh   # isolate the build cache
#
# Exit code is 0 only when every run of every suite exited 0: a crashed or assertion-failed run both
# fail the gate, and the two are reported separately.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$TEXTURA_CANGJIE_ROOT"

RUNS="${TEXTURA_STRESS_RUNS:-50}"
SUITES="${TEXTURA_STRESS_SUITES:-textura.shell textura.views.sop}"
PATHS="${TEXTURA_STRESS_PATHS:-src/shell src/views/sop}"
TARGET_DIR="${TEXTURA_STABILITY_TARGET_DIR:-target}"
TARGET_ARGS=()
[ -n "$TARGET_DIR" ] && TARGET_ARGS=(--target-dir "$TARGET_DIR")
BIN_DIR="$TARGET_DIR/release/unittest_bin"
LOG_DIR="${TEXTURA_STRESS_LOG_DIR:-$TARGET_DIR/stability-logs}"

say() { printf '%s\n' "$*"; }

say "stability gate: runs=$RUNS suites='$SUITES' bin=$BIN_DIR"

# One build for the whole sweep: the loop below must not pay compilation per run, and a build failure
# has to be reported as a build failure, not as a "crash".
# shellcheck disable=SC2086
if [ "${TEXTURA_STRESS_SKIP_BUILD:-0}" = "1" ]; then
  # Reuse the binaries already in the target directory. Useful when another worker is mid-edit in a
  # package this gate does not own: the sweep still measures the code that was last built, and the
  # report says so instead of silently testing someone else's half-written tree.
  say "build skipped (TEXTURA_STRESS_SKIP_BUILD=1): using the binaries already in $BIN_DIR"
else
  cjpm test --no-run -j "${JOBS:-$(nproc)}" "${TARGET_ARGS[@]}" $PATHS >"${TARGET_DIR}/stability-build.log" 2>&1 ||
    { say "BUILD FAILED — see ${TARGET_DIR}/stability-build.log"; exit 2; }
  say "build ok"
fi

mkdir -p "$LOG_DIR"
total_runs=0
total_passed=0
total_crashed=0
total_failed=0
declare -a CRASH_SIGNS=()

for suite in $SUITES; do
  binary="$BIN_DIR/$suite"
  if [ ! -x "$binary" ]; then
    say "missing test binary: $binary"
    exit 2
  fi
  crashed=0
  failed=0
  for i in $(seq 1 "$RUNS"); do
    log="$LOG_DIR/$suite.$i.log"
    # A non-zero status is data here, not an error, so errexit is suspended around the run.
    set +e
    xvfb-run -a -s "-screen 0 1440x900x24" "$binary" >"$log" 2>&1
    rc=$?
    set -e
    total_runs=$((total_runs + 1))
    if [ "$rc" -eq 0 ]; then
      total_passed=$((total_passed + 1))
      rm -f "$log"
    elif [ "$rc" -ge 128 ]; then
      crashed=$((crashed + 1))
      total_crashed=$((total_crashed + 1))
      # Keep the crashing run: its runtime line is the whole point of the exercise.
      sign=$(sed -n 's/.*catched unhandled \(SIG[A-Z]*\).*/\1/p' "$log" | head -1)
      sign="${sign:-signal$((rc - 128))}"
      top=$(sed -n 's/^.* E \(Check failed:.*\)$/\1/p; s/^.* E \+#0 \+\(.*\)$/#0 \1/p' "$log" | head -1)
      CRASH_SIGNS+=("$suite#$i $sign ${top:-no-runtime-line}")
      say "CRASH $suite#$i $sign ${top:-no-runtime-line} -> $log"
    else
      failed=$((failed + 1))
      total_failed=$((total_failed + 1))
      say "FAIL  $suite#$i exit=$rc -> $log"
    fi
  done
  say "suite $suite: runs=$RUNS crashed=$crashed failed=$failed"
done

say "----"
say "runs=$total_runs passed=$total_passed crashed=$total_crashed failed=$total_failed"
if [ "$total_crashed" -ne 0 ] || [ "$total_failed" -ne 0 ]; then
  say "STATUS: FAIL"
  exit 1
fi
say "STATUS: PASS (fail=0 crash=0)"
