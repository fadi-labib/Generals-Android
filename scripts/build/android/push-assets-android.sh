#!/usr/bin/env bash
# Push retail Zero Hour assets to the connected Android device.
#
# Usage: ./scripts/build/android/push-assets-android.sh [ASSET_DIR]
#   ASSET_DIR defaults to ~/GeneralsX/GeneralsZH (see scripts/get-assets.sh).
# Environment:
#   GX_FONTS  fonts dir (default ~/GeneralsX/ios-staging/fonts; run
#             scripts/build/ios/stage-fonts.sh once to create it)
#   GX_UNCOMPRESSED_TEXTURES  RGBA8 texture overlay for non-BCn GPUs:
#             auto (default, push only on non-Adreno) | 1 (force) | 0 (skip)
set -euo pipefail

SRC="${1:-${HOME}/GeneralsX/GeneralsZH}"
FONTS="${GX_FONTS:-${HOME}/GeneralsX/ios-staging/fonts}"
DST="/sdcard/GeneralsZH"

[[ -d "${SRC}" ]] || { echo "ERROR: asset dir ${SRC} not found (run scripts/get-assets.sh)" >&2; exit 1; }
compgen -G "${SRC}/*.big" >/dev/null || { echo "ERROR: no .big archives in ${SRC}" >&2; exit 1; }
[[ -d "${FONTS}" ]] || { echo "ERROR: fonts not staged at ${FONTS} (run scripts/build/ios/stage-fonts.sh)" >&2; exit 1; }
adb get-state >/dev/null || { echo "ERROR: no device" >&2; exit 1; }

# Stage a filtered copy so Windows-only junk never crosses the wire
# (same exclusion list as the iOS packaging script).
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
rsync -a --exclude=".*" \
    --exclude="*.dylib" --exclude="*.so" --exclude="run.sh" --exclude="GeneralsXZH" \
    --exclude="*.dxvk-cache" --exclude="*_d3d9.log" --exclude="MoltenVK_icd.json" \
    --exclude="dxvk.conf" --exclude="fontconfig" \
    --exclude="*.DLL" --exclude="*.dll" --exclude="*.dat" --exclude="*.ico" \
    --exclude="*.bmp" --exclude="*.doc" --exclude="*.lcf" --exclude="Launcher.txt" \
    --exclude="MSS" --exclude="Manuals" --exclude="steamapps" \
    --exclude="steam_appid.txt" --exclude="00000000.*" \
    --exclude="RedistInstallers" --exclude="_CommonRedist" --exclude="*.txt" \
    "${SRC}/" "${STAGE}/"
mkdir -p "${STAGE}/fonts"
cp "${FONTS}"/*.ttf "${STAGE}/fonts/"

echo "==> Pushing $(du -sh "${STAGE}" | cut -f1) to ${DST} (first push takes a while)"
adb shell mkdir -p "${DST}"
adb push --sync "${STAGE}/." "${DST}/"

# --- RGBA8 texture overlay (issue #9 option 1) --------------------------------
# Non-Adreno GPUs (Xclipse/Mali) report textureCompressionBC=0 and cannot sample
# the DXT textures natively. Ship loose uncompressed A8R8G8B8 DDS that override
# the .big copies (FileSystem::openFile prefers loose files). Gated: auto by GPU
# (no /dev/kgsl-3d0 = non-Adreno) unless GX_UNCOMPRESSED_TEXTURES forces (1) or
# disables (0). See transcode-textures-rgba8.py.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)/build/android-textures-rgba8"
push_overlay=0
case "${GX_UNCOMPRESSED_TEXTURES:-auto}" in
  1) push_overlay=1 ;;
  0) echo "==> RGBA8 overlay disabled (GX_UNCOMPRESSED_TEXTURES=0)" ;;
  *) if [[ -n "$(adb shell 'ls /dev/kgsl-3d0 2>/dev/null' | tr -d '\r')" ]]; then
       echo "==> Adreno GPU (kgsl) detected; skipping RGBA8 overlay (Turnip has native BCn)"
     else
       push_overlay=1
     fi ;;
esac

if [[ "${push_overlay}" == 1 ]]; then
  echo "==> Building RGBA8 texture overlay (cached; first run takes minutes)"
  python3 "${SCRIPT_DIR}/transcode-textures-rgba8.py" --asset-dir "${SRC}" --out-dir "${OVERLAY_DIR}"
  if [[ -d "${OVERLAY_DIR}/Art" ]]; then
    echo "==> Pushing RGBA8 overlay ($(du -sh "${OVERLAY_DIR}/Art" | cut -f1)) to ${DST}/Art"
    adb push --sync "${OVERLAY_DIR}/Art/." "${DST}/Art/"
  else
    echo "WARNING: overlay build produced no ${OVERLAY_DIR}/Art; nothing to push" >&2
  fi
fi

echo "==> Done. Verify:"
adb shell "ls ${DST}/*.big | head -5 && ls ${DST}/fonts | head -3 && ls -d ${DST}/ZH_Generals 2>/dev/null || echo 'WARNING: ZH_Generals/ missing (base-game data REQUIRED)'"
