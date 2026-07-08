# Android RGBA8 Texture Overlay (Option 1) — Design

**Date:** 2026-07-08
**Status:** Approved (design), pending implementation plan
**Author:** Fadi Labib

## Goal

Let non-Adreno Android GPUs (Samsung Xclipse/Exynos, ARM Mali) — which report
`textureCompressionBC = 0` — sample the game's textures **without** relying on
DXVK's runtime BC decode. Do this by transcoding the game's BC1/BC2/BC3 (DXT1/3/5)
DDS textures to uncompressed **A8R8G8B8** DDS **offline on the PC**, and delivering
them as **loose files** that override the `.big` archives at load time.

This is issue #9's "Option 1". It trades ~1.5–2 GB of on-device storage for
eliminating per-texture runtime BC emulation (load-time and potential per-frame
GPU savings). It does **not** reduce memory (RGBA8 is the footprint DXVK already
uses after emulation).

## Non-goals

- No `.big` repacking. We rely on loose-file override.
- No engine or DXVK source changes.
- No ASTC/ETC2 path (that is issue #9 "Option 2", explicitly not chosen).
- No change to the Adreno/Turnip path — Adreno keeps native BCn by default.

## Key facts (verified during design)

- **Loose files override archives.** `FileSystem::openFile`
  (`Core/GameEngine/Source/Common/System/FileSystem.cpp:191`) tries
  `TheLocalFileSystem` first and only falls to `TheArchiveFileSystem` when the
  loose file is absent. So a loose `Art/Textures/foo.dds` shadows the copy inside
  `TexturesZH.big`.
- **On Android the game `chdir`s to `/sdcard/GeneralsZH`**
  (`GeneralsMD/Code/Main/SDL3Main.cpp:517`), so that dir is the local filesystem
  root. Loose overrides go there.
- **Texture archives:** `TexturesZH.big` (213 MB, 3496 DDS + 50 TGA) and
  `W3DZH.big` (181 MB, model textures). DDS are **DXT1/DXT5, all mipmapped**
  (e.g. 256×256 mips=9). Internal names use `\` separators, e.g.
  `Art\Textures\aaslab2.dds`.
- TGA entries are already uncompressed → **not transcoded** (they sample fine).
- **Tools present:** `python3` + Pillow 10.2 (decodes DXT1/3/5). No `texconv`.
- **Adreno detection:** `/dev/kgsl-3d0` exists only on Qualcomm (confirmed absent
  on the Exynos S22 Ultra). Same signal the DXVK loader gate uses.

## Architecture

Two components, both PC-side:

### 1. Transcoder — `scripts/build/android/transcode-textures-rgba8.py`

Pure-Python, no new dependencies beyond Pillow.

**Input:** the asset dir (default `~/GeneralsX/GeneralsZH`). Scans **all `*.big`**
for DXT-compressed `.dds` entries. Scanning all archives (not an allowlist) means
terrain/UI/model textures are covered without maintaining a per-archive list; the
scan is a cheap header parse, cost is in decode.

**BIG parsing:** `BIGF` magic, big-endian `count` and per-entry `(offset, size)`
followed by a NUL-terminated name. Read each entry's bytes in place (no full
extraction to disk).

**Per-DDS transcode:**
1. Read the DDS header; act only on FourCC `DXT1`/`DXT3`/`DXT5`. Anything else
   (uncompressed DDS, unknown FourCC, cubemap/volume flags) is **skipped** —
   no loose override emitted, so DXVK/`.big` handles it unchanged.
2. Decode the **top level** to RGBA via Pillow.
3. Regenerate the **full mip chain** to match the source `dwMipMapCount`
   (box filter = 2×2 average per level, each dim `max(1, dim // 2)`). Preserving mips is
   mandatory — omitting them causes worse shimmering than the anisotropy issue.
4. Write an uncompressed **A8R8G8B8** DDS:
   - `DDSD_CAPS|HEIGHT|WIDTH|PIXELFORMAT|PITCH|MIPMAPCOUNT`,
     `dwPitchOrLinearSize = width*4`, `dwMipMapCount = N`.
   - Pixel format `DDPF_RGB|DDPF_ALPHAPIXELS`, `dwRGBBitCount=32`,
     masks R=`0x00ff0000` G=`0x0000ff00` B=`0x000000ff` A=`0xff000000`.
   - Caps `DDSCAPS_TEXTURE|COMPLEX|MIPMAP`.
   - Pixel bytes written **B,G,R,A** per texel (little-endian ARGB / D3D
     `A8R8G8B8` memory order), mip levels concatenated top→smallest.
5. Output to `build/android-textures-rgba8/Art/Textures/<name>.dds` (backslashes
   → forward slashes; original archive-relative directory preserved).

**Caching:** a stamp file `build/android-textures-rgba8/.source-stamp` records each
scanned `.big`'s path/size/mtime. If unchanged, skip the whole pass. (First run is
the only slow one — minutes for ~3.5k+ textures.)

**Self-check:** an `assert`-based `--selftest` that transcodes one synthetic
DXT1 and one DXT5 buffer and verifies the output DDS header fields and that a
re-decoded texel matches the source within BC tolerance.

### 2. push-assets integration — `scripts/build/android/push-assets-android.sh`

- New step: if the overlay should ship, run the transcoder (cached) then
  `adb push build/android-textures-rgba8/Art /sdcard/GeneralsZH/Art`.
- **Gating:**
  - Default: push the overlay **only if the device is non-Adreno** —
    `adb shell '[ -e /dev/kgsl-3d0 ]'` returns non-zero.
  - Opt-in override: `GX_UNCOMPRESSED_TEXTURES=1` forces the overlay even on
    Adreno.
  - Opt-out: `GX_UNCOMPRESSED_TEXTURES=0` skips it everywhere.
- Existing `--exclude` handling is untouched; the overlay is an additive push.

## Data flow

```
*.big (DXT DDS)
   └─ transcode-textures-rgba8.py (decode BC → RGBA, regen mips, write A8R8G8B8)
        └─ build/android-textures-rgba8/Art/Textures/*.dds   (cached)
             └─ push-assets (gated on non-Adreno / flag)
                  └─ /sdcard/GeneralsZH/Art/Textures/*.dds    (loose)
                       └─ FileSystem::openFile → LocalFileSystem wins over .big
                            └─ engine loads RGBA8; DXVK maps A8R8G8B8 natively
```

## Error handling

- **Pillow missing:** transcoder exits non-zero with an install hint;
  push-assets aborts the overlay step (base assets still push).
- **Unknown/unsupported DDS:** skip that entry, log it, leave the `.big` version.
  A summary line reports counts (transcoded / skipped / failed).
- **Device offline / adb missing:** handled by push-assets' existing checks.
- **Partial transcode:** stamp is written only after a clean full pass, so an
  interrupted run re-runs rather than shipping a partial overlay.

## Testing / verification

- **Unit (`--selftest`):** one runnable assert-based check (per ponytail) —
  synthetic DXT1+DXT5 → verify header fields + a decoded texel round-trips.
- **On-device:**
  1. Push overlay to the Xclipse S22 Ultra; confirm a known texture now resolves
     from the loose file (rename-test or file-precedence check).
  2. Launch → skirmish → visual check: no regression, mips present (no shimmer).
  3. Compare in-game FPS with vs without the overlay to quantify the win.
- **Negative:** on an Adreno device with no flag, confirm the overlay is **not**
  pushed (stays lean on native BCn).

## Size / performance

- Overlay ≈ **1.5–2 GB** loose DDS (DXT1 8×, DXT5 4× expansion + mips).
- First transcode: minutes (one-time, cached).
- Push: one `adb push` of a directory tree; ~minutes over USB.
- Runtime: eliminates DXVK BC emulation for overridden textures; expected
  load-time reduction and possible per-frame GPU savings on Xclipse/Mali.

## Rollout

1. Add transcoder script + `--selftest`.
2. Wire the gated overlay step into push-assets.
3. Validate on the Xclipse S22 Ultra (visual + FPS), and confirm Adreno skips it.
4. Document the `GX_UNCOMPRESSED_TEXTURES` flag in push-assets header + issue #9.
