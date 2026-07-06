#!/usr/bin/env bash
# Fetch a prebuilt Mesa Turnip Vulkan driver package (adrenotools ADPKG format)
# for Adreno 6xx/7xx (arm64). This is the analogue of fetch-moltenvk.sh for iOS:
# it downloads a driver blob at build time so nothing binary is committed to git.
#
# Provenance: K11MCH1/AdrenoToolsDrivers — the reference Turnip build repo cited in
# the Phase 0 renderer research (§2.2). Turnip is Mesa's open-source Vulkan 1.3
# driver for Qualcomm Adreno (freedreno); MIT-licensed, so bundling is permitted.
# The Adreno 650 (a6xx) is Turnip's rock-solid tier.
#
# Output: build/android-turnip/pkg/  containing meta.json + libvulkan_freedreno.so
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
OUT_DIR="${PROJECT_ROOT}/build/android-turnip"
PKG_DIR="${OUT_DIR}/pkg"

# Pinned Turnip release. Override with TURNIP_URL to try a different build.
TURNIP_TAG="${TURNIP_TAG:-v25.3.0-rc.11}"
TURNIP_ASSET="${TURNIP_ASSET:-Turnip_v25.3.0_R11.zip}"
TURNIP_URL="${TURNIP_URL:-https://github.com/K11MCH1/AdrenoToolsDrivers/releases/download/${TURNIP_TAG}/${TURNIP_ASSET}}"

mkdir -p "${OUT_DIR}"
ZIP="${OUT_DIR}/$(basename "${TURNIP_ASSET}")"

if [[ ! -f "${ZIP}" ]]; then
    echo "==> Downloading Turnip: ${TURNIP_URL}"
    curl -fL "${TURNIP_URL}" -o "${ZIP}"
else
    echo "==> Using cached ${ZIP}"
fi

rm -rf "${PKG_DIR}"; mkdir -p "${PKG_DIR}"
unzip -o -j "${ZIP}" -d "${PKG_DIR}" >/dev/null

# The ADPKG carries meta.json + the driver .so. libraryName in meta.json names it.
DRIVER_SO="$(find "${PKG_DIR}" -name '*.so' | head -1)"
[[ -n "${DRIVER_SO}" ]] || { echo "ERROR: no .so in Turnip package" >&2; exit 1; }
[[ -f "${PKG_DIR}/meta.json" ]] || { echo "ERROR: no meta.json in Turnip package" >&2; exit 1; }

# Artifact verification (never trust the filename): arm64 + actually Turnip/freedreno.
readelf -h "${DRIVER_SO}" | grep -q AArch64 || { echo "ERROR: driver .so is not arm64" >&2; exit 1; }
# Capture strings BEFORE grepping: `grep -q` exits early on match and SIGPIPEs
# `strings`, which under `set -o pipefail` would fail the whole pipeline even
# though the match was found (same trap documented in package-android-zh.sh).
DRIVER_STRINGS="$(strings "${DRIVER_SO}")"
grep -qiE 'turnip|freedreno|mesa' <<<"${DRIVER_STRINGS}" || {
    echo "ERROR: driver .so does not look like Mesa Turnip/freedreno" >&2; exit 1; }

echo "==> Turnip package ready in ${PKG_DIR}:"
ls -1 "${PKG_DIR}"
echo "==> meta.json:"; cat "${PKG_DIR}/meta.json"; echo
echo "==> driver: $(basename "${DRIVER_SO}") ($(readelf -h "${DRIVER_SO}" | awk '/Machine/{print $2,$3}'))"
