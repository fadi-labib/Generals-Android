#!/usr/bin/env bash
# Verify the Android build environment (Ubuntu primary host).
#
# Usage: ./scripts/build/android/check-android-env.sh
# Environment:
#   ANDROID_NDK_HOME   NDK r27 LTS root (contains build/cmake/android.toolchain.cmake)
#   ANDROID_SDK_ROOT   SDK root (platform-tools/adb, build-tools, platforms)
#   VCPKG_ROOT         full vcpkg clone
set -eu

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${ANDROID_NDK_HOME:-}" ]] || fail "ANDROID_NDK_HOME not set (install NDK r27 LTS via sdkmanager 'ndk;27.2.12479018')"
[[ -f "${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" ]] || fail "NDK toolchain file missing under ANDROID_NDK_HOME"
grep -qs "Pkg.Revision = 27" "${ANDROID_NDK_HOME}/source.properties" || echo "WARNING: NDK is not r27 LTS ($(grep Pkg.Revision "${ANDROID_NDK_HOME}/source.properties" 2>/dev/null || echo unknown))"

[[ -n "${ANDROID_SDK_ROOT:-}" ]] || fail "ANDROID_SDK_ROOT not set"
command -v adb >/dev/null || [[ -x "${ANDROID_SDK_ROOT}/platform-tools/adb" ]] || fail "adb not found (SDK platform-tools)"

[[ -n "${VCPKG_ROOT:-}" ]] || fail "VCPKG_ROOT not set (full clone, not shallow)"
[[ -f "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" ]] || fail "vcpkg toolchain missing under VCPKG_ROOT"

command -v cmake >/dev/null || fail "cmake not found"
command -v ninja >/dev/null || fail "ninja not found"
command -v java >/dev/null || fail "java (JDK 17+) not found"

ADB="$(command -v adb || echo "${ANDROID_SDK_ROOT}/platform-tools/adb")"
if ! "${ADB}" get-state >/dev/null 2>&1; then
    echo "WARNING: no device connected (needed for install/run tasks, not for builds)"
fi

echo "Android environment OK"
