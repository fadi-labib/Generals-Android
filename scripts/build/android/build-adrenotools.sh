#!/usr/bin/env bash
# Build libadrenotools + its linker-namespace hooks for arm64-android.
#
# libadrenotools (github.com/bylaws/libadrenotools) lets an unprivileged Android
# app load a *custom* Vulkan driver (Mesa Turnip) from its own storage, bypassing
# the stock Qualcomm driver. It is the delivery mechanism ratified in the Phase 0
# renderer research (§2.2) to give DXVK a Vulkan 1.3 adapter on the Adreno 650
# (the stock driver only exposes Vulkan 1.1, which DXVK 2.6 rejects).
#
# Outputs (arm64-v8a), copied to build/android-adrenotools/out/:
#   libadrenotools.so     - the API (adrenotools_open_libvulkan)
#   libhook_impl.so       - shared hook implementation
#   libmain_hook.so       - the driver-substitution hook (loaded into libvulkan's ns)
#   libfile_redirect_hook.so, libgsl_alloc_hook.so - optional feature hooks
# These MUST all ship in the APK's nativeLibraryDir; see package-android-zh.sh.
#
# No built binaries are committed. This script (re)produces them from the pinned
# submodule at references/libadrenotools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SRC_DIR="${PROJECT_ROOT}/references/libadrenotools"
BUILD_DIR="${PROJECT_ROOT}/build/android-adrenotools"
OUT_DIR="${BUILD_DIR}/out"

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must be set (e.g. \$ANDROID_SDK_ROOT/ndk/27.2.12479018)}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-29}"

[[ -f "${SRC_DIR}/CMakeLists.txt" ]] || {
    echo "ERROR: ${SRC_DIR} missing. Run: git submodule update --init --recursive references/libadrenotools" >&2
    exit 1
}
# linkernsbypass is a nested submodule; without it the build fails at add_subdirectory.
[[ -f "${SRC_DIR}/lib/linkernsbypass/CMakeLists.txt" ]] || {
    echo "ERROR: nested submodule lib/linkernsbypass missing. Run: git -C ${SRC_DIR} submodule update --init --recursive" >&2
    exit 1
}

echo "==> Configuring libadrenotools (arm64-v8a, API ${ANDROID_PLATFORM})"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM="android-${ANDROID_PLATFORM}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON

echo "==> Building"
cmake --build "${BUILD_DIR}" --parallel

mkdir -p "${OUT_DIR}"
# Collect every produced .so (adrenotools + hooks) into out/ for the packager.
found=0
while IFS= read -r -d '' so; do
    cp -f "${so}" "${OUT_DIR}/"
    echo "  produced $(basename "${so}")"
    found=1
done < <(find "${BUILD_DIR}" -name '*.so' -not -path "${OUT_DIR}/*" -print0)
[[ ${found} -eq 1 ]] || { echo "ERROR: no .so artifacts produced" >&2; exit 1; }

# Verify arch of the main lib.
readelf -h "${OUT_DIR}/libadrenotools.so" | grep -q AArch64 || {
    echo "ERROR: libadrenotools.so is not arm64" >&2; exit 1; }

echo "==> libadrenotools artifacts in ${OUT_DIR}:"
ls -1 "${OUT_DIR}"
