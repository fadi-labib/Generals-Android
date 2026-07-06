#!/usr/bin/env bash
# Push retail Zero Hour assets to the connected Android device.
#
# Usage: ./scripts/build/android/push-assets-android.sh [ASSET_DIR]
#   ASSET_DIR defaults to ~/GeneralsX/GeneralsZH (see scripts/get-assets.sh).
# Environment:
#   GX_FONTS  fonts dir (default ~/GeneralsX/ios-staging/fonts; run
#             scripts/build/ios/stage-fonts.sh once to create it)
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
echo "==> Done. Verify:"
adb shell "ls ${DST}/*.big | head -5 && ls ${DST}/fonts | head -3 && ls -d ${DST}/ZH_Generals 2>/dev/null || echo 'WARNING: ZH_Generals/ missing (base-game data REQUIRED)'"
