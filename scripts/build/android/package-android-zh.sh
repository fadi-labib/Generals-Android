#!/usr/bin/env bash
# Package the Android build of Zero Hour into a debug APK and optionally install it.
#
# Flow: verify artifacts -> copy .so's into jniLibs -> copy SDL3 Java glue ->
#       gradle assembleDebug -> optional adb install.
# Usage: ./scripts/build/android/package-android-zh.sh [--install]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/android-vulkan"
ANDROID_DIR="${PROJECT_ROOT}/android"
JNILIBS="${ANDROID_DIR}/app/jniLibs/arm64-v8a"
SDL_JAVA_SRC="${BUILD_DIR}/_deps/sdl3-src/android-project/app/src/main/java"
SDL_JAVA_DST="${ANDROID_DIR}/app/sdl-java"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

"${SCRIPT_DIR}/check-android-env.sh"

# NOTE: the game lib lands under GeneralsMD/Code/Main/, not GeneralsMD/ directly.
GAME_LIB="${BUILD_DIR}/GeneralsMD/Code/Main/libmain.so"
[[ -f "${GAME_LIB}" ]] || { echo "ERROR: ${GAME_LIB} missing - build android-vulkan first" >&2; exit 1; }
# Artifact check, not exit-code trust: right arch, entry point exported.
readelf -h "${GAME_LIB}" | grep -q AArch64 || { echo "ERROR: libmain.so is not arm64" >&2; exit 1; }
# Capture nm's output before grepping it: with `set -o pipefail`, `grep -q` exiting
# early after a match (on a ~40k-symbol dynsym table) SIGPIPEs `nm`, and pipefail then
# reports the pipeline as failed even though the match was found. Capturing first avoids it.
NM_DYNSYMS="$(nm -D "${GAME_LIB}")"
grep -q "SDL_main" <<<"${NM_DYNSYMS}" || { echo "ERROR: libmain.so does not export SDL_main" >&2; exit 1; }

rm -rf "${JNILIBS}" "${SDL_JAVA_DST}"
mkdir -p "${JNILIBS}"
copy_lib() {  # copy_lib <glob> <required:1|0>
    local matched=0 f
    for f in $1; do [[ -f "$f" ]] && { cp "$f" "${JNILIBS}/"; matched=1; echo "  embedded $(basename "$f")"; }; done
    [[ $matched -eq 1 || $2 -eq 0 ]] || { echo "ERROR: required lib not found: $1" >&2; exit 1; }
}
copy_lib "${GAME_LIB}" 1
copy_lib "${BUILD_DIR}/_deps/sdl3-build/libSDL3.so*" 1
copy_lib "${BUILD_DIR}/_deps/sdl3_image-build/libSDL3_image.so*" 1
copy_lib "${BUILD_DIR}/_deps/openal_soft-build/libopenal.so*" 1
copy_lib "${BUILD_DIR}/libgamespy.so" 0
# Versioned .so names (libSDL3.so.0) are not loadable from an APK: keep bare .so only.
for f in "${JNILIBS}"/*.so.*; do [[ -e "$f" ]] && rm "$f"; done

mkdir -p "${SDL_JAVA_DST}"
cp -R "${SDL_JAVA_SRC}/org" "${SDL_JAVA_DST}/"
echo "  copied SDL3 Java glue"

( cd "${ANDROID_DIR}" && gradle assembleDebug --console=plain )
APK="${ANDROID_DIR}/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "${APK}" ]] || { echo "ERROR: APK not produced" >&2; exit 1; }
echo "==> APK ready: ${APK}"

if [[ ${DO_INSTALL} -eq 1 ]]; then
    adb install -r "${APK}"
    PKG="$(grep -oP "applicationId project.findProperty\('GX_APP_ID'\) \?: '\K[^']+" "${ANDROID_DIR}/app/build.gradle")"
    adb shell pm grant "${PKG}" android.permission.READ_EXTERNAL_STORAGE || true
    adb shell pm grant "${PKG}" android.permission.WRITE_EXTERNAL_STORAGE || true
    echo "==> Installed ${PKG} (storage permissions granted)"
fi
