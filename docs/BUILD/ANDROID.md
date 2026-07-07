# GeneralsX - Android Build Instructions (arm64-v8a)

> **Status: THE GAME RENDERS AND PLAYS.** As of 2026-07-07 the full game runs on a Galaxy
> Tab S7+ (Adreno 650): main menu with animated shell map, skirmish lobby, and a live
> skirmish match at native 2800×1752, ~30-60 FPS — via DXVK (D3D8→Vulkan) on a bundled
> Mesa Turnip driver loaded rootlessly through libadrenotools. See
> [Current Status](#current-status), the [rendering pipeline](#rendering-pipeline-phase-3),
> and [Known issues & remaining work](#known-issues--remaining-work).

![Skirmish match on Galaxy Tab S7+](screenshots/android-tab-s7plus-ingame.png)

> **Continuing this work?** This document is the complete handover: the
> [rendering pipeline](#rendering-pipeline-phase-3) is the mental model, and
> [Development Loop, Debugging & Traps](#development-loop-debugging--traps) carries the
> hard-won lessons from the sessions that got the port here.
> Touch controls (gestures, state machine, design rationale, debugging):
> [docs/port/TOUCH_CONTROLS.md](../port/TOUCH_CONTROLS.md).

## Prerequisites

### System Requirements

- **Ubuntu** host (primary; this guide is Ubuntu-specific for paths/package names)
- Android device: **arm64-v8a, API 29+** (tested on Galaxy S22 and Galaxy Tab S7+, see
  [Devices Profiled](#devices-profiled))
- ~10 GB free disk space (NDK + SDK + vcpkg build artifacts)

### 1. Android NDK r27 LTS + SDK

Install the command-line tools and platform-tools under `~/Android/Sdk`, then pull the pinned
NDK via `sdkmanager`:

```bash
sdkmanager --sdk_root=$HOME/Android/Sdk "platform-tools" "ndk;27.2.12479018"
```

Verify:

```bash
ls ~/Android/Sdk/ndk/27.2.12479018/build/cmake/android.toolchain.cmake
~/Android/Sdk/platform-tools/adb --version
```

### 2. Gradle 8.9

Download the Gradle 8.9 distribution and unpack it to `~/Android/gradle/gradle-8.9` (the
packaging step drives `gradle assembleDebug` directly, no wrapper is checked in).

```bash
ls ~/Android/gradle/gradle-8.9/bin/gradle
```

### 3. JDK 21

```bash
sudo apt install openjdk-21-jdk
java -version
```

### 4. vcpkg (full clone)

A **full** (non-shallow) vcpkg clone is required — the overlay triplet and ports registry
lookups need history/manifest files a shallow clone omits.

```bash
git clone https://github.com/microsoft/vcpkg.git ~/vcpkg
~/vcpkg/bootstrap-vcpkg.sh
```

### 5. cmake, ninja

```bash
sudo apt install cmake ninja-build
```
(Tested with cmake 3.28.)

### 6. Environment variables

Add to `~/.zshrc` (or the equivalent shell profile):

```bash
# Android port toolchain
export ANDROID_SDK_ROOT=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_SDK_ROOT/ndk/27.2.12479018
export VCPKG_ROOT=$HOME/vcpkg
export PATH=$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$HOME/Android/gradle/gradle-8.9/bin:$PATH
```

### 7. Verify the environment

```bash
./scripts/build/android/check-android-env.sh
```

This checks `ANDROID_NDK_HOME` (and warns if the NDK isn't r27 LTS), `ANDROID_SDK_ROOT`/`adb`,
`VCPKG_ROOT` (full clone, not shallow), `cmake`/`ninja`/`java`, and warns (non-fatally) if no
device is attached.

---

## Building

### Clone the Repository

```bash
git clone https://github.com/ammaarreshi/Generals-Mac-iOS-iPad.git GeneralsX
cd GeneralsX
```

### Submodules (required for the renderer)

```bash
git submodule update --init --recursive references/fbraz3-dxvk references/libadrenotools
```

`references/fbraz3-dxvk` is the DXVK fork that gets `Patches/dxvk-android.patch` applied at
build time (Turnip loader + Android WSI surface path); `references/libadrenotools` is the
rootless custom-Vulkan-driver loader.

### Configure and Build

```bash
cmake --preset android-vulkan
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
```

The `android-vulkan` preset (`CMakePresets.json`) builds arm64-v8a, API 29+, against the
`arm64-android` overlay vcpkg triplet, with SDL3 + OpenAL + FFmpeg enabled. The DXVK
cross-build (meson, `libdxvk_d3d8.so`/`libdxvk_d3d9.so`) is driven from `cmake/dx8.cmake` as
part of this build; it applies `Patches/dxvk-android.patch` idempotently to the submodule.

### Renderer support libraries (one-time per checkout)

```bash
./scripts/build/android/build-adrenotools.sh   # libadrenotools + linker-namespace hooks
./scripts/build/android/fetch-turnip.sh        # pinned Mesa Turnip ADPKG (Vulkan 1.3, MIT)
```

Both outputs are packaged into the APK by `package-android-zh.sh`; nothing binary is
committed to git.

The game builds as a **shared library** (SDL3's Android model runs the game inside
`SDLActivity`, not as a standalone executable):

```
build/android-vulkan/GeneralsMD/Code/Main/libmain.so
```

---

## Packaging

```bash
./scripts/build/android/package-android-zh.sh [--install]
```

This script:

1. Runs `check-android-env.sh`
2. Verifies `libmain.so` is a real arm64 build exporting `SDL_main` (`readelf -h` + `nm -D`,
   not just a nonzero exit code — a silent wrong-arch or missing-symbol build has bitten this
   port before)
3. Copies `libmain.so`, `libSDL3.so`, `libSDL3_image.so`, `libopenal.so` (and `libgamespy.so`
   if present) into `android/app/jniLibs/arm64-v8a/`
4. Copies the SDL3 Android Java glue into `android/app/sdl-java/`
5. Runs `gradle assembleDebug`
6. With `--install`, runs `adb install -r` and grants storage permissions

Output APK (~225 MB debug build):

```
android/app/build/outputs/apk/debug/app-debug.apk
```

App id: `com.generalsx.generalszh`. Main activity: `.GeneralsXZHActivity`.

---

## Assets

The engine needs the retail Zero Hour `.big` archives plus the base-game (`Generals`) data
under `ZH_Generals/`, and staged fonts. Two ways to get there:

### Option A — Steam (scripted)

```bash
./scripts/get-assets.sh
```

This is **Steam-only** — it expects a Steam library with Zero Hour installed and copies from
there. If you don't have a Steam copy, use Option B.

### Option B — Manual copy (retail disc/EA copy)

If you have a non-Steam retail install (e.g. an EA copy on USB media), lay it out manually:

```
~/GeneralsX/GeneralsZH/            # Zero Hour install: *.big archives + Data/
~/GeneralsX/GeneralsZH/ZH_Generals/ # base Generals game data (REQUIRED alongside ZH)
```

Copy the `.big` archives (`generalszh.big`, `W3DZH.big`, `MapsZH.big`, `AudioZH.big`, etc.)
and `Data/` from the Zero Hour install into `~/GeneralsX/GeneralsZH/`, and the base game's
files into `~/GeneralsX/GeneralsZH/ZH_Generals/`. This is exactly the layout
`push-assets-android.sh` (below) expects, and matches the desktop-build asset layout
documented in [MACOS.md](MACOS.md#5-game-files).

### Fonts

```bash
./scripts/build/ios/stage-fonts.sh
```

Stages Liberation fonts (renamed to match the retail font names, e.g. `arial.ttf`) to
`~/GeneralsX/ios-staging/fonts` — reused as-is for Android (same fontconfig-free
`fonts/`-directory font resolution as iOS).

### Push to device

```bash
./scripts/build/android/push-assets-android.sh [ASSET_DIR]
```

- Defaults to `~/GeneralsX/GeneralsZH` (override with the positional arg or `GX_FONTS` env var
  for the fonts dir).
- Requires a connected device (`adb get-state`).
- Stages a filtered copy (excludes Windows-only junk: `.dylib`/`.so`/installers/redist/etc. —
  same exclusion list as the iOS packaging script) plus the staged fonts, then
  `adb push --sync` to `/sdcard/GeneralsZH`.
- Pushes **~2.9 GB in ~67 seconds** over USB (observed).
- Verifies afterward by listing `.big` files, `fonts/`, and the required `ZH_Generals/` dir on
  the device.

---

## Device Setup

### USB debugging

Enable Developer Options + USB debugging on the device, connect via USB, accept the RSA
fingerprint prompt, and confirm:

```bash
adb devices
```

### Samsung sideload gotcha

Samsung devices commonly reject a debug-signed sideload with:

```
INSTALL_FAILED_VERIFICATION_FAILURE
```

Fix (one-time, per device):

1. Disable Play Protect's install-time verifier for adb installs:
   ```bash
   adb shell settings put global verifier_verify_adb_installs 0
   ```
2. Turn off **Samsung Auto Blocker** on-device (Settings -> Security and privacy -> Auto
   Blocker) — it independently blocks unauthorized app installs regardless of the verifier
   setting above.

---

## Headless Verification (Phase 2 gate)

Two harnesses exist. Both prove the non-graphics engine (CompatLib, both filesystems, .big
parsing, INI loading, deterministic sim loop) runs correctly on-device — no rendering
required.

### 1. Replay playback harness

```bash
./scripts/build/android/run-headless-replay.sh <replay.rep> [timeout_s]
```

Pushes a `.rep` to the device, launches `-headless -replay <path>`, and polls for completion
via **two** independent signals: an exit-code file
(`/sdcard/GeneralsZH/last-run-exitcode.txt`, written by `gxRedirectStdioToLogcat`'s caller in
`GeneralsMD/Code/Main/SDL3Main.cpp` after `GameMain()` returns) and a logcat completion
marker (tag `GeneralsX`). Reports PASS (exit 0) / FAIL / timeout, and dumps the sim-evidence
log lines (replay progress, frame/game-time, any CRC mismatch).

### 2. Self-recorded AI-vs-AI skirmish (the path that actually reaches exit 0)

A **macOS-recorded** replay played back on Android hits a genuine cross-platform determinism
mismatch (bionic libm vs Apple libm transcendental-function drift accumulating over hundreds
of frames — expected and documented, not an Android defect: see
[ANDROID_PORT_FINDINGS_2026-07-06.md §7](../WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md)).
To get a same-platform, bit-exact replay, the engine can record its own AI-vs-AI skirmish
headlessly and then play that recording back on the same device:

```bash
adb shell "am start -n com.generalsx.generalszh/.GeneralsXZHActivity \
  --es args '-headless -skirmishReplay Maps/Whiteout.map -skirmishFrames 1500'"
```

This fires a 2-AI free-for-all skirmish on the named map, runs it to the given frame cap
(fixed seed, deterministic), and writes a `.rep` under the app's private storage. Pulling that
file and feeding it back into `run-headless-replay.sh` closes the loop: **Android-recorded,
Android-played, no cross-platform libm involved.**

### 3. One-command smoke test (record + replay + assert)

```bash
./scripts/build/android/smoke-test-android.sh [timeout_s]
```

Wraps both harnesses above into a single regression gate against the **currently-installed**
app (no build/install step): records a fresh skirmish, pulls the `.rep`, replays it through
`run-headless-replay.sh`, and asserts exit 0, no CRC-mismatch/desync in logcat, and a
non-trivial amount of game time simulated. Prints `SMOKE TEST: PASS` / `SMOKE TEST: FAIL:
<reason>`. Run it after any engine change as a quick "is the headless sim still correct?"
check.

---

## Current Status

| Phase | Scope | Status |
|---|---|---|
| Phase 0 | Renderer route research + decision | ✅ Done — `require-turnip` (see [renderer-route decision](#renderer-route-decision)) |
| Phase 1 | Build system, Gradle shell app, packaging, app launches | ✅ Done — app runs `SDL_main` on-device (logcat: `Running main function SDL_main from library .../libmain.so`) |
| Phase 2 | Headless verification (non-graphics engine) | ✅ Done — Android-recorded AI-vs-AI skirmish replay (Maps/Whiteout.map, 1500 frames / 00:50 game time) plays back to exit 0, no CRC mismatch |
| Phase 3 | Renderer bring-up (DXVK cross-build, Turnip bundling, WSI, crash fixes) | ✅ **Done — the game renders and plays** (2026-07-07, Tab S7+/Adreno 650): main menu + shell map, skirmish lobby, live match, ~30-60 FPS at 2800×1752, driven end-to-end by touch |
| Phase 4+ | Touch controls polish, lifecycle (pause/resume), audio verification, perf, non-Adreno devices | ⏳ Next — see [Known issues & remaining work](#known-issues--remaining-work) |

### Gate evidence

- **P0**: route decided — `require-turnip` (native-arm64 dxvk-native + bundled Mesa Turnip via
  libadrenotools). See [§5 of the renderer research doc](../WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md#5-decision).
- **P1**: app launches and runs the engine's `SDL_main` entry point on-device (confirmed via
  `adb logcat`).
- **P2**: Android-recorded skirmish replay (`Maps/Whiteout.map`, `-skirmishFrames 1500`)
  played back via `run-headless-replay.sh` on the Galaxy Tab S7+ → exit 0, 1500 frames
  simulated (00:50 game time), no CRC mismatch.

### Devices profiled

| Device | SoC / GPU | Vulkan | `textureCompressionBC` | Notes |
|---|---|---|---|---|
| Galaxy S22 (SM-S908B, Exynos) | Xclipse 920 | 1.3 | FALSE | No BCn, no Turnip (not Adreno) — asset-transcode fallback territory |
| Galaxy Tab S7+ (SM-T970) | Snapdragon 865 / Adreno 650, Android 13 | 1.3 | **FALSE on stock driver** | Empirically corrects the research doc's `[CLAIM]` that Adreno 650 stock exposes BCn — it does not. Makes `require-turnip` **necessary**, not optional, for this device. Primary Phase 3 target (Adreno 650 = Turnip's rock-solid 6xx tier). |

---

## Rendering Pipeline (Phase 3)

```
Game (DirectX 8 calls)
  → libdxvk_d3d8.so / libdxvk_d3d9.so        (DXVK 2.6 fork, meson cross-build,
                                               Patches/dxvk-android.patch)
  → Vulkan 1.3 via Mesa Turnip               (bundled libvulkan_freedreno.so,
                                               loaded rootlessly by libadrenotools —
                                               stock Adreno 650 driver only exposes 1.1)
  → VK_KHR_android_surface → ANativeWindow   (SDL3 SurfaceView)
```

Key mechanics, each of which was a hard-won lesson:

1. **Turnip via adrenotools** (`SDL3Main.cpp: gxSetupTurnipDriver` + the patch's
   `vulkan_loader.cpp`): the app stages the bundled Turnip .so into its private files dir and
   exports `GENERALSX_ADRENOTOOLS_*` env vars; DXVK's Vulkan loader dlopens
   `adrenotools_open_libvulkan` instead of the stock `libvulkan.so`.
2. **One Vulkan loader, not two** (patch's `wsi_window_sdl3.cpp`): SDL loads its own copy of
   the system Vulkan loader, so `SDL_Vulkan_CreateSurface` would hand DXVK's Turnip
   `VkInstance` to a *different* loader. On Android the patched WSI fetches the
   `ANativeWindow*` from SDL window properties and calls `vkCreateAndroidSurfaceKHR` resolved
   from DXVK's own loader.
3. **Deferred surface creation** (`SDL3Main.cpp` sets
   `DXVK_CONFIG=d3d9.deferSurfaceCreation = True`): an `ANativeWindow` accepts exactly **one**
   producer connection. The engine's device-creation retry loop (W3DDisplay::init /
   dx8wrapper) can construct a doomed first device — its depth-format default `D3DFMT_D32` is
   rejected by the driver — whose implicit swapchain has already claimed the window; the
   failure path leaks the connection and every subsequent device then fails forever with
   `VK_ERROR_NATIVE_WINDOW_IN_USE_KHR` (black screen, game running headless behind it). With
   deferred creation only the device that actually presents ever touches the window.
4. **Shared libc++** (`meson.build` patch hunk + `ANDROID_STL=c++_shared`): DXVK must NOT
   statically link libstdc++ on Android, or a `DxvkError` thrown inside DXVK has its own
   RTTI and gets swallowed by `catch(...)` in libmain.so instead of surfacing the real error.
5. **Zero-initialized heap** (`GameMemory.cpp`): desktop builds route global `new` through the
   engine's memory pool, which memsets allocations to 0 — and the 2003 codebase silently
   relies on that. Bionic `malloc` returns dirty memory; Android now uses `calloc` so the
   hundreds of constructors that leave members uninitialized keep working.

### Debugging tip: dxvk.conf without rebuilding

DXVK reads `$PWD/dxvk.conf`, and the game's working directory is `/sdcard/GeneralsZH` — so
you can A/B any DXVK option on-device with no rebuild:

```bash
printf 'd3d9.deferSurfaceCreation = True\n' > /tmp/dxvk.conf
adb push /tmp/dxvk.conf /sdcard/GeneralsZH/dxvk.conf
adb shell am force-stop com.generalsx.generalszh
adb shell am start -n com.generalsx.generalszh/.GeneralsXZHActivity
```

(Note: the `DXVK_CONFIG` env var set by `SDL3Main.cpp` wins over the file for the *same* key;
other keys merge. This is exactly how the deferSurfaceCreation root cause was confirmed
before baking the fix into code.)

---

## Development Loop, Debugging & Traps

### Iteration cycle (~2 min once the toolchain is set up)

```bash
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
./scripts/build/android/package-android-zh.sh --install
adb shell am force-stop com.generalsx.generalszh
adb logcat -c && adb shell am start -n com.generalsx.generalszh/.GeneralsXZHActivity
```

### Key files (the Android-specific surface area)

| File | Role |
|---|---|
| `GeneralsMD/Code/Main/SDL3Main.cpp` | Entry point: Turnip staging, env setup (`DXVK_WSI_DRIVER`, `DXVK_CONFIG`, adrenotools vars), SDL init, window creation |
| `GeneralsMD/Code/GameEngineDevice/Source/SDL3GameEngine.cpp` | Event loop; `GX_TOUCH_UI` guards the touch→mouse gesture translator + background render-pause (shared with iOS). Full design/debugging doc: [`docs/port/TOUCH_CONTROLS.md`](../port/TOUCH_CONTROLS.md) |
| `Patches/dxvk-android.patch` | ALL DXVK changes (loader, WSI, meson, portability guards). Applied idempotently by `cmake/dx8.cmake` to the `references/fbraz3-dxvk` submodule |
| `cmake/dx8.cmake` | Drives the DXVK meson cross-build inside the cmake build |
| `scripts/build/android/*.sh` | env check, adrenotools build, Turnip fetch, APK packaging, asset push, headless replay harness |
| `android/app/` | Gradle shell app (SDLActivity subclass `GeneralsXZHActivity`) |

**Rule: the DXVK submodule working tree must stay byte-identical to the patch.** If you
edit DXVK code, regenerate: `cd references/fbraz3-dxvk && git diff >
../../Patches/dxvk-android.patch`, and verify `diff <(git diff)
../../Patches/dxvk-android.patch` says identical.

### Debugging toolbox (earned the hard way)

- **Game log lines** all come out under logcat tag `GeneralsX` (stdio is redirected);
  DXVK's own `info:`/`warn:`/`err:` lines are inside that tag too. The pump filters
  `[INI]`/`[SUBSYS]`/`[GX-ISSUE144]` boot spam by default (~85% quieter); launch with the
  `GENERALSX_VERBOSE` env set for the full firehose. `err:`/`warn:`/`ERROR`/`FATAL` are
  never filtered.
- **Boot health check** (after ~40 s):
  `adb logcat -d | grep -cE "Actual swapchain properties"` → must be ≥1;
  `grep -c NATIVE_WINDOW_IN_USE` → must be 0; `grep -c "beginning of crash"` → 0.
- **A/B any DXVK option with no rebuild** — see the
  [dxvk.conf tip](#debugging-tip-dxvkconf-without-rebuilding) above. This is how the
  black-screen root cause was confirmed in minutes.
- **Screenshots work**: `adb exec-out screencap -p > shot.png` captures the Vulkan
  SurfaceView fine. A ~20 KB PNG = black screen; multi-MB = real content.
- **Touch via adb**: `input tap` has a 0 ms down-up — the gesture translator's deferred
  click lands in the same frame as the hover and menus DON'T activate. Use
  `adb shell input swipe X Y X Y 150` to emulate a real finger. Menu buttons need ONE
  such tap (if two are needed again, the translator regressed).
- **Audio without ears**: `adb shell dumpsys media.audio_flinger` — look for the app's
  uid with tracks not in standby. The OpenAL backend list shows in logcat tag `openal`
  ("Supported backends: opensl, null, wave" — opensl must be chosen).
- **Two devices in DXVK logs** (`grep -c "Device properties:"`): two is currently NORMAL
  at boot and load-bearing — see [#8](https://github.com/fadi-labib/Generals-Android/issues/8)
  and Known issues below. Three+ means something new is wrong.

### Traps that will bite again if forgotten

- `__ANDROID__` **also defines** `__linux__`. Any `#if defined(__linux__)` desktop
  workaround silently applies to Android — that's exactly how audio got muted (a
  desktop-only `ALSOFT_DRIVERS` override forced the null backend). When touching platform
  guards, always ask "and what does this do on Android?"
- In release builds `WWASSERT` is a no-op — engine invariants like "device must be null
  before Create_Device" silently don't hold.
- DXVK can return `D3D_OK` with a **null back buffer** (`_Get_DX8_Back_Buffer`); guard
  every back-buffer consumer (see `W3DSmudge.cpp` for the pattern: degrade the effect,
  don't crash).
- The 2003 codebase assumes `new` returns zeroed memory (desktop routes through a
  memset-ing pool allocator; Android uses `calloc`). A nonsense-pointer SIGSEGV in a
  constructor-adjacent path usually means "uninitialized member desktop got away with"
  (see the `Pathfinder`, `W3DBridgeBuffer`, `W3DSmudgeManager` fixes).
- Samsung sideload verification failures → see [Device Setup](#device-setup).

---

## Known Issues & Remaining Work

**Resolved during the 2026-07-07 session** (kept here so future readers know these were
real and are fixed, not never-encountered):

- ~~Black screen / `VK_ERROR_NATIVE_WINDOW_IN_USE_KHR` loop~~ → deferred surface creation
  (see [rendering pipeline](#rendering-pipeline-phase-3) point 3).
- ~~Touch needed two taps per menu button~~ → the iOS touch→mouse gesture translator
  (tap-select, drag-box, long-press right-click, two-finger pan, pinch zoom) is now enabled
  on Android (`GX_TOUCH_UI` in `SDL3GameEngine.cpp`); a real finger activates in one tap.
  (`adb shell input tap` still needs two — its 0 ms down-up delivers hover+click in one
  frame; use `input swipe x y x y 150` to emulate a real tap.)
- ~~First tap after boot swallowed / pan-zoom interference / jitter drag-boxes~~ → three
  gesture fixes (commit `ffa4645e9`): the main menu auto-reveals on touch platforms
  (desktop hides it until the mouse moves, which cost touch users their entire first
  tap mid-reveal-transition); two-finger pan and pinch now mode-lock (whichever moves
  first wins — no more zoom ticks while panning or camera drift while pinching); and
  gesture thresholds are physical (~3 mm, DPI-scaled) instead of 8 px (~0.7 mm on this
  panel — fingertip jitter turned taps into accidental drag-boxes).
- ~~Silent audio~~ → Android inherited the Linux desktop `ALSOFT_DRIVERS=pulse,alsa,...`
  workaround (`__ANDROID__` also defines `__linux__`), forcing OpenAL to the null backend.
  Android now keeps default selection and picks OpenSL ES; audio_flinger shows live tracks.
- ~~`D3DRS_PATCHSEGMENTS` warn flood~~ (~72k lines / 12 min) → N-patches are Windows-only.
- Basic lifecycle: home → resume survives with the same process and rendering intact (the
  iOS background render-pause now also guards Android).

**Known issues (2026-07-07):**

- **`MISSING: 'GUI:CustomMission'`** label in the Solo Play menu — upstream localization gap,
  cosmetic.
- **Two-device boot / 16-bit depth** ([#8](https://github.com/fadi-labib/Generals-Android/issues/8)):
  the engine creates a doomed first device (its `D3DFMT_D32` default is rejected) then a
  surviving `D3DFMT_D16` device. Investigation established the two-device dance is
  **load-bearing** — the 3D shell map renders black with a single device regardless of depth
  (`D24S8`/`D16`) or present mode; the first device's teardown primes Turnip's presenter. It
  is a DXVK/Turnip driver-lifecycle issue, **not** a depth/format one (an earlier "default
  D24S8" idea was disproven on-device). Cosmetic/boot-time only; the game renders fine.
- **Log spam** — *fixed* (`9455765a2`): the stderr→logcat pump now filters
  `[INI]`/`[SUBSYS]`/`[GX-ISSUE144]` boot traces by default (~85% quieter). Set the
  `GENERALSX_VERBOSE` env to restore the full firehose; `err:`/`warn:`/`ERROR`/`FATAL` are
  never filtered.
- **Audio quality/mix** verified only as "tracks are playing" (audio_flinger); not yet
  listened to by a human.

**Remaining work (Phase 4 candidates)** — tracked as issues on
[fadi-labib/Generals-Android](https://github.com/fadi-labib/Generals-Android/issues):

- Touch gesture tuning under real gameplay (drag-box vs pan feel, long-press timing) —
  [#11](https://github.com/fadi-labib/Generals-Android/issues/11).
- Campaign / Generals Challenge / video playback testing (untested on Android) —
  [#12](https://github.com/fadi-labib/Generals-Android/issues/12).
- Performance: FPS currently ~30-60 at native 2800×1752; render-scale option —
  [#13](https://github.com/fadi-labib/Generals-Android/issues/13).
- Non-Adreno devices: Xclipse 920 (Galaxy S22) has no BCn texture support and no Turnip —
  needs an asset-transcode fallback (Phase 0 research) —
  [#9](https://github.com/fadi-labib/Generals-Android/issues/9).
- Deeper lifecycle: rotation, split-screen, low-memory kills, save-on-pause.

---

## Regression Checklist (definition of "still works")

After any change, verify on-device:

1. Boot reaches the main menu with the animated shell map (screenshot is multi-MB).
2. `Actual swapchain properties` in logcat; zero `NATIVE_WINDOW_IN_USE`; zero
   `beginning of crash`.
3. One 150 ms swipe-tap on SOLO PLAY opens the submenu (single-tap works).
4. Skirmish: map select → PLAY GAME → in-game HUD with FPS counter and running
   game clock.
5. `dumpsys media.audio_flinger` shows the app's tracks active (not standby).
6. HOME → relaunch: same PID, rendering resumed.

---

## Renderer-Route Decision

Full research and decision: [`docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md`](../WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md),
decision in §5. Route: **`require-turnip`** — native-arm64 dxvk-native (mainline DXVK 2.x,
SDL3 WSI) with bundled Mesa Turnip loaded rootless via `libadrenotools`, targeting Qualcomm
Adreno flagships (Vulkan 1.3 floor). Codebase findings that fed this plan:
[`docs/WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md`](../WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md).

---

## Related Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build/android/check-android-env.sh` | Verify NDK/SDK/vcpkg/cmake/ninja/java + device state |
| `scripts/build/android/package-android-zh.sh` | Verify `libmain.so` artifact, embed .so's + SDL3 Java glue, `gradle assembleDebug`, optional install |
| `scripts/build/android/push-assets-android.sh` | Push filtered retail assets + staged fonts to `/sdcard/GeneralsZH` |
| `scripts/build/android/run-headless-replay.sh` | Push + launch `-headless -replay`, poll for completion, report PASS/FAIL |
| `scripts/build/android/smoke-test-android.sh` | One-command regression gate: record a fresh skirmish, replay it, assert exit 0 + CRC-clean |
| `scripts/get-assets.sh` | Steam-only asset fetch |
| `scripts/build/ios/stage-fonts.sh` | Stage Liberation fonts under retail font names (shared with iOS) |
| `CMakePresets.json` (`android-vulkan`) | Build preset (arm64-v8a, API 29+, SDL3 + OpenAL + FFmpeg) |

---

*See the [Dev Blog](../../DEV_BLOG/) for detailed session-by-session technical notes.*
