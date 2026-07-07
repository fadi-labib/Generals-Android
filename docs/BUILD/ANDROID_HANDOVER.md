# Android Port — AI/Engineer Handover

> Written 2026-07-07 at the end of the session that took the port from "black screen"
> to "playable skirmish with sound and touch". Everything here is verified on real
> hardware. Read this top-to-bottom before touching anything; it encodes the traps
> that cost hours.

## TL;DR — where the port stands

**Zero Hour is playable on Android** (Galaxy Tab S7+, Snapdragon 865 / Adreno 650,
Android 13): main menu with animated shell map, skirmish lobby, live matches at
~30–60 FPS, native 2800×1752, OpenSL ES audio, single-tap touch controls
(tap-select, drag-box, long-press right-click, two-finger pan, pinch zoom),
home→resume survives. Zero crashes across multi-minute soaks and repeated boots.

Branch: `feature/android-phase3-renderer` on `github.com/fadi-labib/Generals-Android`
(upstream: `ammaarreshi/Generals-Mac-iOS-iPad`, main branch `main`).

The session's commits, newest first — each message is a root-cause writeup, read them:

| Commit | What |
|---|---|
| `30fc4d9b6` | docs: status update for touch/audio/lifecycle |
| `c8be2d416` | **feat: iOS touch gestures + lifecycle pause + OpenSL audio on Android** |
| `2b82a75b2` | docs: README + ANDROID.md + on-device screenshots |
| `b1186e717` | fix: D3DRS_PATCHSEGMENTS log flood (N-patches Windows-only) |
| `75bd7fd87` | **fix: defer DXVK surface creation — the black-screen root cause** |
| `2b7bb0020` | **fix: zero-init heap (calloc) + missing-back-buffer guards** |
| `26eb36590` | feat: Mesa Turnip via libadrenotools (Vulkan 1.3 on Adreno 650) |
| `e8c7bb989`…`ccdeab493` | DXVK arm64-android cross-build chain |

## Mental model (read this before debugging anything graphical)

```
Game (D3D8) → libdxvk_d3d8/d3d9.so → Vulkan 1.3 (bundled Mesa Turnip via
libadrenotools) → vkCreateAndroidSurfaceKHR → ANativeWindow (SDL3 SurfaceView)
```

Five load-bearing mechanics, each of which broke the port until fixed:

1. **Stock Adreno 650 driver only exposes Vulkan 1.1; DXVK 2.6 requires 1.3.**
   We bundle Mesa Turnip and load it rootlessly with libadrenotools.
   `SDL3Main.cpp:gxSetupTurnipDriver()` stages the driver + sets
   `GENERALSX_ADRENOTOOLS_*` env vars; the patched DXVK `vulkan_loader.cpp` dlopens
   it. Grep logcat for `Turnip Adreno` to confirm the right driver enumerated.
2. **SDL and DXVK must not use two different Vulkan loaders for one window.**
   The patched `wsi_window_sdl3.cpp` bypasses `SDL_Vulkan_CreateSurface` on Android:
   it pulls the `ANativeWindow*` from SDL window properties and calls
   `vkCreateAndroidSurfaceKHR` resolved from DXVK's own (Turnip) loader.
3. **An ANativeWindow accepts exactly ONE producer connection.** The engine's
   device-retry loop (`W3DDisplay::init` → `dx8wrapper Set_Render_Device`) creates a
   doomed first device — its `D3DFMT_D32` depth default is rejected — whose implicit
   swapchain claims the window; the failure path leaks the connection, and every
   later device fails forever with `VK_ERROR_NATIVE_WINDOW_IN_USE_KHR` while the game
   runs headless behind a black screen. Fix: `SDL3Main.cpp` sets
   `DXVK_CONFIG=d3d9.deferSurfaceCreation = True` (surface created at first Present
   only). If you ever see `NATIVE_WINDOW_IN_USE` again, suspect a second
   swapchain/device being created while one is alive.
4. **DXVK must link libc++ SHARED on Android** (`meson.build` patch hunk +
   `ANDROID_STL=c++_shared` + the packaging script shipping one `libc++_shared.so`).
   Otherwise `DxvkError` has private RTTI and real errors vanish into `catch(...)`.
5. **The 2003 codebase assumes `new` returns zeroed memory** (desktop builds route
   through a memset-ing pool allocator). Bionic malloc is dirty →
   `GameMemory.cpp` uses `calloc` on Android. If you hit a nonsense-pointer SIGSEGV
   in a constructor-adjacent path, think "uninitialized member that desktop got away
   with" first (see `Pathfinder`, `W3DBridgeBuffer`, `W3DSmudgeManager` fixes).

## Key files (Android-specific surface area)

| File | Role |
|---|---|
| `GeneralsMD/Code/Main/SDL3Main.cpp` | Entry point: Turnip staging, env setup (`DXVK_WSI_DRIVER`, `DXVK_CONFIG`, adrenotools vars), SDL init, window creation |
| `GeneralsMD/Code/GameEngineDevice/Source/SDL3GameEngine.cpp` | Event loop; `GX_TOUCH_UI` guards the touch→mouse gesture translator + background render-pause (shared with iOS) |
| `Patches/dxvk-android.patch` | ALL DXVK changes (loader, WSI, meson, portability guards). Applied idempotently by `cmake/dx8.cmake` to the `references/fbraz3-dxvk` submodule |
| `cmake/dx8.cmake` | Drives the DXVK meson cross-build inside the cmake build |
| `scripts/build/android/*.sh` | env check, adrenotools build, Turnip fetch, APK packaging, asset push, headless replay harness |
| `android/app/` | Gradle shell app (SDLActivity subclass `GeneralsXZHActivity`) |
| `docs/BUILD/ANDROID.md` | Full build guide + known issues — keep it updated |

**Rule: the submodule working tree must stay byte-identical to the patch.** If you
edit DXVK code, regenerate: `cd references/fbraz3-dxvk && git diff >
../../Patches/dxvk-android.patch`, and verify `diff <(git diff)
../../Patches/dxvk-android.patch` says identical.

## Build & deploy loop (Ubuntu host)

```bash
# One-time: see docs/BUILD/ANDROID.md Prerequisites (NDK r27, Gradle 8.9, JDK 21, vcpkg)
git submodule update --init --recursive references/fbraz3-dxvk references/libadrenotools
cmake --preset android-vulkan
./scripts/build/android/build-adrenotools.sh
./scripts/build/android/fetch-turnip.sh
./scripts/build/android/push-assets-android.sh          # once; assets → /sdcard/GeneralsZH

# Iteration cycle (~2 min):
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
bash scripts/build/android/package-android-zh.sh
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop com.generalsx.generalszh
adb logcat -c && adb shell am start -n com.generalsx.generalszh/.GeneralsXZHActivity
```

Device on this desk: Galaxy Tab S7+ (`adb devices` → `R52NC03AXPW`, SM-T970).

## Debugging toolbox (earned the hard way)

- **Game log lines** all come out under logcat tag `GeneralsX` (stdio is redirected).
  DXVK's own `info:`/`warn:`/`err:` lines are inside that tag too. Useful filter:
  `adb logcat -d | grep GeneralsX | grep -vE "\[INI\]|SUBSYS|GX-ISSUE144"`.
- **Boot health check** (after ~40 s):
  `adb logcat -d | grep -cE "Actual swapchain properties"` → must be ≥1;
  `grep -c NATIVE_WINDOW_IN_USE` → must be 0; `grep -c "beginning of crash"` → 0.
- **A/B any DXVK option with NO rebuild**: DXVK reads `$PWD/dxvk.conf` and the
  game's cwd is `/sdcard/GeneralsZH` — `adb push dxvk.conf /sdcard/GeneralsZH/` and
  restart the app. (The `DXVK_CONFIG` env set in code wins for the same key.)
  This is how the black-screen root cause was confirmed in minutes.
- **Screenshots work**: `adb exec-out screencap -p > shot.png` captures the Vulkan
  SurfaceView fine. A ~20 KB PNG = black screen; multi-MB = real content.
- **Touch via adb**: `input tap` has a 0 ms down-up — the gesture translator's
  deferred click lands in the same frame as the hover and menus DON'T activate.
  Use `adb shell input swipe X Y X Y 150` to emulate a real finger. Menu buttons
  need ONE such tap (if you see two needed again, the translator regressed).
- **Audio without ears**: `adb shell dumpsys media.audio_flinger` — look for the
  app's uid with tracks not in standby. OpenAL backend list shows in logcat tag
  `openal` ("Supported backends: opensl, null, wave" — opensl must be chosen).
- **Two devices in DXVK logs** = count `grep -c "Device properties:"`. Two is
  currently NORMAL at boot (doomed D32 device + surviving D16 device). One would be
  ideal (see next steps). Three+ means something new is wrong.

## Traps that will bite you again if forgotten

- `__ANDROID__` **also defines** `__linux__`. Any `#if defined(__linux__)` desktop
  workaround silently applies to Android — that's exactly how audio got muted
  (desktop-only `ALSOFT_DRIVERS` forced the null backend). When touching platform
  guards, always ask "and what does this do on Android?"
- In release builds `WWASSERT` is a no-op — engine invariants like "device must be
  null before Create_Device" silently don't hold.
- DXVK can return `D3D_OK` with a **null back buffer** (`_Get_DX8_Back_Buffer`);
  guard every back-buffer consumer (see `W3DSmudge.cpp` for the pattern:
  degrade the effect, don't crash).
- Samsung sideload: `INSTALL_FAILED_VERIFICATION_FAILURE` → disable Play Protect
  adb verification + Samsung Auto Blocker (see ANDROID.md Device Setup).
- Git push from this machine: `GH_TOKEN` env is the OWNER'S WORK account. The repo's
  `.git/config` overrides the github.com credential helper with the personal
  `fadi-labib` keyring token. Don't "fix" that back.

## Prioritized next steps (with implementation hints)

1. **Real-gameplay touch tuning.** The translator constants
   (`LONG_PRESS_MS=600`, `TAP_DEAD_ZONE_PX=8`, `PINCH_STEP_RATIO=0.06` in
   `SDL3GameEngine.cpp`) were tuned for iPhone/iPad; validate on the tablet in a
   real match (build a base, box-select, issue moves). The 8 px dead zone may be
   too small at 2800×1752.
2. **Kill the doomed first device** (quality + boot time): the engine requests
   fullscreen `2800×1599` which matches no enumerated mode, so `Find_Z_Mode` fails
   and `dx8wrapper.cpp:~1401` blindly defaults depth to `D3DFMT_D32` → rejected →
   retry lands on 16-bit `D3DFMT_D16` (possible z-fighting). Fix ideas: default to
   `D3DFMT_D24S8` on non-Win32 (Turnip supports it — DXVK logs the D16S8→D24S8
   mapping), or fix the mode-matching for native panel sizes. Success = ONE
   `Device properties:` block per boot and a D24S8 depth buffer.
3. **Boot-time log spam**: `[INI]`/`[SUBSYS]`/`[GX-ISSUE144]` fprintf tracing
   floods logcat for ~40 s per boot. iOS solved this with a filtered stderr sink in
   `SDL3Main.cpp` (see the `TARGET_OS_IPHONE` diagnostic block) — Android could
   reuse it or gate the traces behind an env var.
4. **Campaign / Generals Challenge / video playback** untested on Android. Video =
   FFmpeg path (from TheSuperHackers lineage); expect format/paths issues first.
5. **Perf headroom**: currently ~30–60 FPS at native res. Options: render-scale
   option (engine renders lower, swapchain scales), or cap the shell-map FPS.
   Profile with `adb shell dumpsys gfxinfo com.generalsx.generalszh` first.
6. **Non-Adreno devices** (Galaxy S22 / Xclipse 920): no Turnip, no BCn texture
   support on the stock driver → needs the asset-transcode fallback researched in
   Phase 0 (`docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md`). Big.
7. **Repo hygiene for publication**: `GeneralsReplays` is a dangling gitlink
   (mode 160000, no `.gitmodules` entry) — `git rm --cached GeneralsReplays`
   (a `.gitignore` entry already exists). Consider squash/merge strategy for
   `feature/android-phase3-renderer` → `main`.

## Definition of "still works" (regression checklist)

After any change, verify on-device:

1. Boot reaches the main menu with the animated shell map (screenshot is multi-MB).
2. `Actual swapchain properties` in logcat; zero `NATIVE_WINDOW_IN_USE`; zero
   `beginning of crash`.
3. One 150 ms swipe-tap on SOLO PLAY opens the submenu (single-tap works).
4. Skirmish: map select → PLAY GAME → in-game HUD with FPS counter and running
   game clock.
5. `dumpsys media.audio_flinger` shows the app's tracks active (not standby).
6. HOME → relaunch: same PID, rendering resumed.
