# GeneralsX - Android Build Instructions (arm64-v8a)

> **Status: Phases 0-2 complete and verified on real hardware.** The engine builds, packages,
> installs, and runs its full non-graphics simulation loop (filesystem, .big archives, INI,
> game logic, deterministic sim) on-device. Rendering (Phase 3+) is not wired up yet — see
> [Current Status](#current-status) and the [renderer-route decision](#renderer-route-decision).

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
git clone https://github.com/fbraz3/GeneralsX.git
cd GeneralsX
```

### Configure and Build

```bash
cmake --preset android-vulkan
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
```

The `android-vulkan` preset (`CMakePresets.json`) builds arm64-v8a, API 29+, against the
`arm64-android` overlay vcpkg triplet, with SDL3 + OpenAL + FFmpeg enabled.

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
| Phase 3+ | Renderer bring-up (Turnip bundling), touch/lifecycle, audio/video, parity polish | ⏳ Next — to be planned from the renderer-route decision |

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
