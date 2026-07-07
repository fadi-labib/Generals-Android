#!/usr/bin/env bash
# One-command on-device regression smoke test for the Android port.
#
# This is the standing "did the headless engine break?" gate: it records a fresh
# AI-vs-AI skirmish on the connected device using the CURRENTLY-INSTALLED app,
# then feeds that freshly-recorded replay back through the on-device replay
# harness and asserts a clean, non-trivial, self-consistent playback.
#
# It does NOT build or (re)install anything -- it validates whatever APK is
# currently on the device. Run it after any engine change (renderer, packaging,
# CompatLib, ...) as a quick correctness gate for the non-graphics simulation.
#
# Phases:
#   1. RECORD  - launch `-headless -skirmishReplay Maps/Whiteout.map
#                -skirmishFrames 1500`, which drives a real 2-AI skirmish through
#                the full engine and serializes it to a .rep in the app's
#                private files dir (see da02937d1). Wait for completion via the
#                exit-code file / logcat marker, then pull the .rep with run-as.
#   2. REPLAY  - feed that .rep through run-headless-replay.sh (reused as-is:
#                same am-start quoting, same completion detection).
#   3. ASSERT  - replay exit code 0, no CRC-mismatch/desync in logcat, and a
#                non-trivial amount of game time simulated (not an instant exit).
#
# Usage: ./scripts/build/android/smoke-test-android.sh [timeout_s]
#
# Environment:
#   ANDROID_SDK_ROOT   Must be set (adb on PATH), e.g.:
#                        export ANDROID_SDK_ROOT=$HOME/Android/Sdk
#                        export PATH=$ANDROID_SDK_ROOT/platform-tools:$PATH
set -euo pipefail

PKG="com.generalsx.generalszh"
ACTIVITY=".GeneralsXZHActivity"
DEV_ASSET_DIR="/sdcard/GeneralsZH"
DEV_RC_FILE="${DEV_ASSET_DIR}/last-run-exitcode.txt"
# Non-debug builds always record to a fixed slot (RecorderClass::getLastReplayFileName()
# only rotates filenames in RTS_DEBUG builds); a skirmish with no TheNetwork always
# lands here, overwritten on every record run.
APP_REPLAY_FILE="files/GeneralsX/GeneralsZH/Replays/00000000.rep"
SKIRMISH_MAP="Maps/Whiteout.map"
SKIRMISH_FRAMES=1500
TIMEOUT="${1:-180}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLAY_HARNESS="${SCRIPT_DIR}/run-headless-replay.sh"

WORKDIR="$(mktemp -d /tmp/android-smoke-test.XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

RECORD_LOG="${WORKDIR}/record-logcat.txt"
REPLAY_LOG="${WORKDIR}/replay-logcat.txt"
PULLED_REP="${WORKDIR}/android-smoke-skirmish.rep"

fail() {
    echo "SMOKE TEST: FAIL: $1" >&2
    exit 1
}

echo "==> [precheck] device connectivity"
adb get-state >/dev/null 2>&1 || fail "no adb device connected"

echo "==> [precheck] app installed (${PKG})"
adb shell pm list packages "${PKG}" | grep -q "^package:${PKG}\$" \
    || fail "${PKG} is not installed on the device"

echo "==> [precheck] assets present at ${DEV_ASSET_DIR}"
adb shell "[ -d ${DEV_ASSET_DIR} ]" \
    || fail "${DEV_ASSET_DIR} not found on device -- push assets first (push-assets-android.sh)"

[[ -x "${REPLAY_HARNESS}" ]] || fail "missing or non-executable ${REPLAY_HARNESS}"

adb shell svc power stayon true >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Phase 1: RECORD a fresh AI-vs-AI skirmish
# ---------------------------------------------------------------------------
echo "==> [record] clearing previous completion marker and replay slot"
adb shell rm -f "${DEV_RC_FILE}" >/dev/null 2>&1 || true
adb shell run-as "${PKG}" rm -f "${APP_REPLAY_FILE}" >/dev/null 2>&1 || true

adb logcat -c
adb shell am force-stop "${PKG}"
echo "==> [record] launching headless skirmish record (${SKIRMISH_MAP}, ${SKIRMISH_FRAMES} frames)..."
# See run-headless-replay.sh for why this must be one device-shell-parsed string
# with the args value single-quoted (otherwise `am` re-splits on the flags).
adb shell "am start -n ${PKG}/${ACTIVITY} --es args '-headless -skirmishReplay ${SKIRMISH_MAP} -skirmishFrames ${SKIRMISH_FRAMES}'" >/dev/null

echo "==> [record] waiting for completion (timeout ${TIMEOUT}s)..."
RECORD_RC=""
END=$(( $(date +%s) + TIMEOUT ))
while [[ $(date +%s) -lt ${END} ]]; do
    RECORD_RC="$(adb shell cat "${DEV_RC_FILE}" 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -n "${RECORD_RC}" ]] && break
    if ! adb shell pidof "${PKG}" >/dev/null 2>&1 \
       && adb logcat -d | grep -qE "FATAL EXCEPTION|SIGSEGV|beginning of crash"; then
        adb logcat -d > "${RECORD_LOG}"
        fail "record phase crashed (see ${RECORD_LOG})"
    fi
    sleep 5
done
adb logcat -d -s GeneralsX AndroidRuntime DEBUG > "${RECORD_LOG}" 2>/dev/null || adb logcat -d > "${RECORD_LOG}"

[[ -n "${RECORD_RC}" ]] || fail "record phase timed out after ${TIMEOUT}s (no completion marker); see ${RECORD_LOG}"
[[ "${RECORD_RC}" == "0" ]] || fail "record phase exited with code ${RECORD_RC} (see ${RECORD_LOG})"
echo "==> [record] PASS: GameMain() returned with code ${RECORD_RC}"

echo "==> [record] pulling recorded replay"
adb shell run-as "${PKG}" test -f "${APP_REPLAY_FILE}" \
    || fail "no .rep produced at ${APP_REPLAY_FILE} after a successful record run"
adb exec-out run-as "${PKG}" cat "${APP_REPLAY_FILE}" > "${PULLED_REP}"
REP_SIZE="$(wc -c < "${PULLED_REP}" | tr -d '[:space:]')"
[[ "${REP_SIZE}" -gt 1024 ]] || fail "recorded replay is suspiciously small (${REP_SIZE} bytes)"
head -c 6 "${PULLED_REP}" | grep -q "GENREP" || fail "recorded file has no GENREP magic -- not a valid replay"
echo "==> [record] pulled ${PULLED_REP} (${REP_SIZE} bytes, GENREP magic OK)"

# ---------------------------------------------------------------------------
# Phase 2: REPLAY the freshly-recorded skirmish
# ---------------------------------------------------------------------------
echo "==> [replay] feeding the recorded skirmish back through $(basename "${REPLAY_HARNESS}")"
REPLAY_RC=0
LOG_OUT="${REPLAY_LOG}" "${REPLAY_HARNESS}" "${PULLED_REP}" "${TIMEOUT}" > "${WORKDIR}/replay-stdout.txt" 2>&1 || REPLAY_RC=$?
cat "${WORKDIR}/replay-stdout.txt"

[[ "${REPLAY_RC}" -eq 0 ]] || fail "replay phase failed (exit ${REPLAY_RC}); see above and ${REPLAY_LOG}"

# ---------------------------------------------------------------------------
# Phase 3: ASSERT clean, non-trivial playback
# ---------------------------------------------------------------------------
echo "==> [assert] checking for CRC mismatch / desync markers"
if grep -qiE "CRC[ _]?mismatch|REPLAY_CRC_MISMATCH|desync" "${REPLAY_LOG}"; then
    fail "CRC mismatch / desync detected in replay logcat (see ${REPLAY_LOG})"
fi

GAME_TIME_LINE="$(grep -iE "Game Time" "${REPLAY_LOG}" | tail -1 || true)"
[[ -n "${GAME_TIME_LINE}" ]] || fail "no 'Game Time' sim-progress evidence found in replay logcat (see ${REPLAY_LOG})"
echo "==> [assert] sim evidence: ${GAME_TIME_LINE}"

# Sanity-check the sim actually ran for a while (${SKIRMISH_FRAMES} frames @ 30fps
# ~= 50s of game time), i.e. it's not a trivial/instant exit. Best-effort: only
# enforced when the MM:SS/MM:SS format is present.
if [[ "${GAME_TIME_LINE}" =~ ([0-9]+):([0-9]+)/([0-9]+):([0-9]+) ]]; then
    ELAPSED_SEC=$(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
    TOTAL_SEC=$(( 10#${BASH_REMATCH[3]} * 60 + 10#${BASH_REMATCH[4]} ))
    [[ "${TOTAL_SEC}" -ge 40 ]] \
        || fail "replay's total game time is too short (${TOTAL_SEC}s; expected ~50s for ${SKIRMISH_FRAMES} frames) -- looks like a trivial/instant exit"
    [[ "${ELAPSED_SEC}" -ge "${TOTAL_SEC}" ]] \
        || fail "replay did not reach its full game time (${ELAPSED_SEC}/${TOTAL_SEC}s)"
fi

echo ""
echo "----- evidence summary -----"
echo "record exit code : ${RECORD_RC}"
echo "replay exit code : ${REPLAY_RC}"
echo "replay .rep size : ${REP_SIZE} bytes"
echo "game time        : ${GAME_TIME_LINE}"
echo "CRC mismatches   : none"
echo "-----------------------------"
echo "SMOKE TEST: PASS"
