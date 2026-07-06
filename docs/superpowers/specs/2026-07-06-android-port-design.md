# Android Port — Design Spec

**Date:** 2026-07-06
**Status:** Approved (brainstormed section-by-section with the project owner)
**Findings basis:** `docs/WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md`
**Template:** the iOS port (`docs/port/PORTING_PLAYBOOK.md`)

## Decisions (locked)

| Question | Decision |
|---|---|
| Definition of done | **iOS parity**: campaign + skirmish + Generals Challenge fully playable with touch controls, native resolution, sound + video |
| Devices | Recent flagships: **API 29+ (Android 10), arm64-v8a only**, decent Vulkan 1.1+ drivers |
| Asset delivery | **adb/MTP push now** (PC fetches via `scripts/get-assets.sh`, copy to app external files dir); **in-app importer post-parity** |
| Renderer risk | **Research pass first** (Phase 0) with an explicit go/pivot gate before engineering |
| Dev host | **Ubuntu primary**; `linux64-deploy` is the fast debug loop (same `__linux__` code paths); macOS secondary |
| Distribution | Sideloaded APK, dev-signed — same posture as the iOS port. No assets distributed, GPL v3 code |

## Architecture

The Android build reuses the existing non-Windows stack wholesale — Android is
Linux, and the codebase's platform isolation was verified by audit (game logic:
1 platform-guarded file; everything Android touches lives in Main /
GameEngineDevice / CompatLib / 4 files of WW3D2 / cmake).

```
GeneralsXZH game code (unchanged)
  ├─ App shell ......... Gradle + SDL3 SDLActivity (Java), landscape-locked,
  │                      game compiled as libmain.so                       [NEW]
  ├─ Entry ............. SDL3Main.cpp + __ANDROID__ blocks: chdir to GameData,
  │                      HOME/user-data wiring, DXVK_STATE_CACHE_PATH,
  │                      DefaultOptions.ini seeding (StaticGameLOD=High,
  │                      TextureReduction=0), -xres/-yres injection (reused) [SMALL]
  ├─ Windowing/input ... SDL3 (first-class Android) + existing iOS touch→mouse
  │                      gesture machine, guards widened to __ANDROID__     [REUSE]
  ├─ Rendering ......... D3D8 → DXVK d3d8/d3d9 (meson cross-build, SDL3 WSI)
  │                      → native Vulkan (NO MoltenVK)                      [CROSS-BUILD]
  ├─ Audio ............. OpenAL Soft (OpenSL/AAudio backend) + FFmpeg       [UNCHANGED]
  ├─ Video ............. FFmpeg                                             [UNCHANGED]
  ├─ Text .............. FreeType + bundled fonts/ dir (iOS locator path;
  │                      no fontconfig on Android)                          [REUSE]
  └─ Files ............. StdLocal/StdBIG file systems unchanged; assets in
                         app external files dir                             [UNCHANGED]
```

Build-system deltas:
- New `android-vulkan` CMake preset mirroring `ios-vulkan`
  (`CMAKE_SYSTEM_NAME=Android`, NDK toolchain, `ANDROID_ABI=arm64-v8a`).
- New overlay triplet `cmake/triplets/arm64-android.cmake` pinning min API 29
  (pattern: `arm64-ios.cmake` pins the iOS deployment target).
- vcpkg deps for the triplet: zlib, glm, gli, freetype, curl[ssl],
  ffmpeg 8.x (existing override); fontconfig excluded (`!android`, like `!ios`).
- Meson cross file `cmake/meson-arm64-android-cross.ini.in` generated from the
  NDK (pattern: the iOS cross file), `-Ddxvk_native_wsi=sdl3` with the
  generated sdl3.pc on PKG_CONFIG_PATH.
- One structural change: a thin `SHARED` wrapper target producing `libmain.so`
  (SDL3's Android contract — SDLActivity loads the game as a shared library).
  All existing static libs unchanged.

## Phases and gates

Every phase ends with a behavioral gate verified on real hardware. Gates are
honest — "it compiles" is never a gate.

**Phase 0 — Ecosystem research (no code).**
Survey: DXVK-on-Android state (dxvk-native forks, Winlator/Termux lineage),
Mesa Turnip vs stock Adreno/Mali drivers, **BCn/DXT texture format support**
(the game's DDS assets require BCn; stock Android drivers largely lack it,
Turnip has emulation), SDL3 Android maturity, prior SDL3+DXVK Android ports.
*Deliverable:* findings doc + **go/pivot decision** on the renderer route
(stock driver / require-Turnip / format-transcode fallback).
*Gate:* renderer route decided on evidence.

**Phase 1 — Toolchain + scaffold.**
Preset, triplet, vcpkg deps building, `libmain.so` wrapper target,
Gradle/SDLActivity shell app, packaging script with `--dev` fast mode
(analog of `package-ios-zh.sh`), install + logcat capture working.
*Gate:* stub app launches on-device with SDL3 initialized.

**Phase 2 — Headless gate.**
Full engine linked into `libmain.so`; assets adb-pushed; run
`-headless -replay` on-device (the harness exists — used in CI with SDL dummy
drivers). Proves CompatLib, both file systems, .big parsing, INI loading, and
game logic on Android with zero graphics risk.
*Gate:* a retail replay simulates to completion with correct CRC on the phone.

**Phase 3 — Renderer bring-up.**
DXVK meson cross-build per the Phase-0 decision; verify `Sdl3WsiDriver` via
`strings` (silent SDL2 fallback is a known trap); dxvk .so's into jniLibs;
`dx8wrapper`'s existing Linux `LoadLibrary("libdxvk_d3d8.so")` branch; ship
dxvk.conf (aniso 16×, logLevel none); Options.ini LOD seeding.
*Gate:* main menu renders at native resolution (the true halfway point).

**Phase 4 — Input + lifecycle.**
Widen the iOS gesture state machine (deferred tap / drag / long-press-RMB /
two-finger-pan / pinch-wheel) and lifecycle-pause guards to `__ANDROID__`;
`SDL_HINT_TOUCH_MOUSE_EVENTS=0` + `SDL_TOUCH_MOUSEID` drop; add Android
surface-lost/recreate handling (background destroys the surface → gate
rendering; `DX8Wrapper::Reset_Device()` on resume if required).
*Gate:* skirmish playable by touch; survives 20 background/resume cycles.

**Phase 5 — Audio + video.**
Expected near-free (platform-neutral code; openal-soft picks OpenSL/AAudio).
Verify streamed-speech EOF behavior (chirp/EVA fix class) and briefing videos.
*Gate:* campaign mission plays with sound, speech, music, and briefing video.

**Phase 6 — Parity polish.**
Campaign + Generals Challenge sweep; memory-pressure watch (Android LMK is
stricter than iOS jetsam; iPad sessions hit ~3 GB resident); performance and
battery sanity; triage against the iOS known-issues list; docs
(`docs/BUILD/ANDROID.md`, playbook addendum).
*Gate:* the iOS-parity definition of done.

**Phase 7 (post-parity) — In-app asset importer.**
SAF folder picker → copy into app storage. Explicitly outside parity scope.

## Verification and testing

- **Artifact checks over exit codes** at every build step:
  `strings libdxvk_d3d9*.so | grep Sdl3WsiDriver`, `readelf -h` (EM_AARCH64),
  `nm -u libmain.so`. The lineage's three worst debugging sessions were all
  silent green-exit failures.
- **Headless replay = standing regression suite**: rerun on-device after the
  renderer, input, and audio phases. Logic determinism must never drift.
- **Standing checks from Phase 4 on**: 10-minute stability run;
  background/resume torture loop.
- Packaging script validates freshness/content of everything it embeds
  (stale-dylib lesson).
- Logging: logcat primary; add the iOS-style capped file sink (`__ANDROID__`
  variant) only if logcat proves insufficient.
- No unit-test scaffolding — the engine has none; the replay harness is stronger.

## Pivot points (decided on evidence, not mid-crisis)

1. **BCn unavailable on target drivers** → ranked: require Turnip-capable
   devices → DXVK-side format emulation → asset-side DDS transcode at
   extract time (last resort — storage and load-time cost).
2. **DXVK cross-build intractable** → investigate upstream/community
   dxvk-native Android patches before writing our own; the fork+patch model
   already exists (`references/fbraz3-dxvk` + `Patches/dxvk-ios.patch`).
3. **Surface-recreate unrecoverable** → engine already has
   `DX8Wrapper::Reset_Device()`; worst case, hard-gate rendering while
   backgrounded exactly like iOS.

## Conventions

All repo rules apply: `// GeneralsX @keyword author DD/MM/YYYY` annotations;
platform code confined to Main / GameEngineDevice / CompatLib / cmake;
conventional-commit titles; ZH-first (Generals backport only for shared
platform code); upstream-offerable pieces kept as reviewable commits; monthly
dev-blog entries; work docs in `docs/WORKDIR/`.

The `endian_compat.h` letoh bugfix
(`docs/WORKDIR/audit/BUG_ENDIAN_COMPAT_LETOH_2026-07-06.md`) lands early as a
standalone one-line-family commit (safe on all current targets) and gets
offered upstream.

## Out of scope

- Cross-platform multiplayer (float determinism — pre-existing, all platforms)
- x86_64 / 32-bit Android ABIs
- Play Store distribution
- The in-app importer beyond Phase 7's minimal SAF flow
