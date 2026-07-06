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
# GeneralsX @build FadiLabib 06/07/2026
# DXVK d3d8/d3d9: dx8wrapper.cpp bare-name dlopen's "libdxvk_d3d8.so" on Android/Linux;
# both must ship in the APK so the dynamic linker resolves them from nativeLibraryDir.
copy_lib "${BUILD_DIR}/libdxvk_d3d8.so" 1
copy_lib "${BUILD_DIR}/libdxvk_d3d9.so" 1
# GeneralsX @build FadiLabib 06/07/2026
# Shared libc++: libmain.so (ANDROID_STL=c++_shared) and the DXVK .so's now all
# NEED libc++_shared.so, so it must ship in the APK or nothing loads. One NDK
# copy for all three -> a DxvkError thrown in DXVK type-matches std::exception in
# libmain.so (single libc++abi/RTTI), surfacing the real Vulkan error.
NDK_LIBCXX="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"
copy_lib "${NDK_LIBCXX}" 1
# GeneralsX @build FadiLabib 07/07/2026 - Mesa Turnip via libadrenotools (Vulkan 1.3).
# adrenotools + its linker-namespace hooks (build-adrenotools.sh) MUST land in
# nativeLibraryDir: adrenotools_open_libvulkan preloads libhook_impl.so and
# libmain_hook.so from hookLibDir (= nativeLibraryDir). All five ship as jniLibs.
ADRENOTOOLS_OUT="${PROJECT_ROOT}/build/android-adrenotools/out"
copy_lib "${ADRENOTOOLS_OUT}/libadrenotools.so" 1
copy_lib "${ADRENOTOOLS_OUT}/libhook_impl.so" 1
copy_lib "${ADRENOTOOLS_OUT}/libmain_hook.so" 1
copy_lib "${ADRENOTOOLS_OUT}/libfile_redirect_hook.so" 1
copy_lib "${ADRENOTOOLS_OUT}/libgsl_alloc_hook.so" 1
# The Turnip driver (fetch-turnip.sh) ships under a lib*-prefixed name so Android
# extracts it to nativeLibraryDir (only lib*.so are extracted). SDL3Main.cpp copies
# it once into the private files dir under its real soname and hands adrenotools the
# path. It is NOT loaded as a NEEDED dependency — it is opened by the Turnip hook.
TURNIP_SO="${PROJECT_ROOT}/build/android-turnip/pkg/vulkan.ad07xx.so"
[[ -f "${TURNIP_SO}" ]] || { echo "ERROR: Turnip driver not found at ${TURNIP_SO} — run scripts/build/android/fetch-turnip.sh" >&2; exit 1; }
cp "${TURNIP_SO}" "${JNILIBS}/libvulkan_freedreno.so"
echo "  embedded libvulkan_freedreno.so (Mesa Turnip driver)"
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
