#!/usr/bin/env bash
# Run a headless replay on the connected Android device and report pass/fail.
#
# This is the Phase 2 gate and the standing on-device regression check: it proves
# the non-graphics engine (CompatLib, filesystems, .big parsing, INI loading,
# game-logic determinism) simulates a real retail replay to completion on Android.
#
# The engine's stdout/stderr are routed to logcat (tag GeneralsX) by
# gxRedirectStdioToLogcat() in GeneralsMD/Code/Main/SDL3Main.cpp, and the exit
# code is also written to /sdcard/GeneralsZH/last-run-exitcode.txt after
# GameMain() returns. This harness uses BOTH: the file for a robust completion
# signal, logcat for the sim-progress evidence.
#
# Usage: ./scripts/build/android/run-headless-replay.sh <replay.rep> [timeout_s]
set -euo pipefail

REP="${1:?usage: run-headless-replay.sh <replay.rep> [timeout_s]}"
TIMEOUT="${2:-600}"
PKG="com.generalsx.generalszh"
ACTIVITY=".GeneralsXZHActivity"
DEV_ASSET_DIR="/sdcard/GeneralsZH"
DEV_REPLAY_DIR="${DEV_ASSET_DIR}/Replays"
DEV_RC_FILE="${DEV_ASSET_DIR}/last-run-exitcode.txt"
LOG_OUT="${LOG_OUT:-/tmp/android-replay-logcat.txt}"

[[ -f "${REP}" ]] || { echo "ERROR: ${REP} not found (see GeneralsReplays/)" >&2; exit 1; }
adb get-state >/dev/null

# Keep the device awake: a screen-off pause can stall the sim loop.
adb shell svc power stayon true >/dev/null 2>&1 || true

adb shell mkdir -p "${DEV_REPLAY_DIR}"
echo "==> Pushing $(basename "${REP}") -> ${DEV_REPLAY_DIR}/test.rep"
adb push "${REP}" "${DEV_REPLAY_DIR}/test.rep" >/dev/null

# Clear the previous run's completion marker so we never read a stale PASS.
adb shell rm -f "${DEV_RC_FILE}" >/dev/null 2>&1 || true

adb logcat -c
adb shell am force-stop "${PKG}"
echo "==> Launching headless replay…"
# NOTE: the whole am command is one string so the device shell — not adb's local
# shell — parses it, and the args value is single-quoted so "-headless -replay
# <path>" reaches am as ONE --es extra instead of being re-split into separate
# am options (which fails with "Unknown option: -r").
adb shell "am start -n ${PKG}/${ACTIVITY} --es args '-headless -replay ${DEV_REPLAY_DIR}/test.rep'" >/dev/null

echo "==> Waiting for completion (timeout ${TIMEOUT}s)…"
END=$(( $(date +%s) + TIMEOUT ))
RESULT=""
RC=""
while [[ $(date +%s) -lt ${END} ]]; do
    # Mechanism B: the exit-code file is the authoritative completion signal.
    # `|| true`: adb shell cat returns non-zero until the file exists, and
    # set -euo pipefail would otherwise abort the whole poll on the first miss.
    RC="$(adb shell cat "${DEV_RC_FILE}" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ -n "${RC}" ]]; then
        RESULT="GameMain() returned with code ${RC}"
        break
    fi
    # Mechanism A: the completion marker on stderr -> logcat (tag GeneralsX).
    if adb logcat -d -s GeneralsX | grep -q "GameMain() returned with code"; then
        RESULT="$(adb logcat -d -s GeneralsX | grep "GameMain() returned with code" | tail -1)"
        break
    fi
    # Crash detection: process gone AND a crash signature in the log.
    if ! adb shell pidof "${PKG}" >/dev/null 2>&1 \
       && adb logcat -d | grep -qE "FATAL EXCEPTION|SIGSEGV|beginning of crash"; then
        RESULT="CRASHED"
        break
    fi
    sleep 5
done

adb logcat -d -s GeneralsX AndroidRuntime DEBUG > "${LOG_OUT}" 2>/dev/null || adb logcat -d > "${LOG_OUT}"
echo "==> Full log: ${LOG_OUT}"

echo "----- sim evidence (replay/frame/time) -----"
grep -iE "Simulating Replay|Game Time|Elapsed Time|Total Time|Simulation of all replays|REPLAY_CRC_MISMATCH|CRC Mismatch|Cannot open replay" "${LOG_OUT}" || echo "(no sim lines found)"
echo "--------------------------------------------"

case "${RESULT}" in
    *"code 0"*)   echo "PASS: ${RESULT}"; exit 0 ;;
    "")           echo "FAIL: timeout after ${TIMEOUT}s (no completion marker)"; exit 2 ;;
    "CRASHED")    echo "FAIL: process crashed (see ${LOG_OUT})"; exit 1 ;;
    *)            echo "FAIL: ${RESULT}"; exit 1 ;;
esac
