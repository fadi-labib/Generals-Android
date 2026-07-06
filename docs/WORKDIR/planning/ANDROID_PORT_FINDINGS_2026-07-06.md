# Android Port — Codebase Findings (2026-07-06 full read-through)

Source material for the Android port plan. Produced by a systematic read of the
port-relevant codebase (~all docs, the full build system, the complete compat
layer, the complete platform device layer, engine core init/loop, plus a
structural sweep of the platform-clean remainder).

---

## 1. What the codebase is

~1.67M lines of C/C++ across 4,268 files. Three trees:

| Tree | Role |
|---|---|
| `Core/` | Shared engine: WWVegas libs, shared GameEngine code, shared GameEngineDevice backends |
| `GeneralsMD/` | Zero Hour — PRIMARY target (`z_generals` → `GeneralsXZH`) |
| `Generals/` | Base game — backport target only (~1,277 files differ from GeneralsMD; CompatLib and SDL3GameEngine are duplicated per-tree) |

Cross-platform stack (identical on Linux/macOS/iOS — this is what Android inherits):

```
Game code (platform-clean)
  ├─ Windowing/input .... SDL3 3.4.2 (FetchContent) + SDL3_image 3.4.0 (ANI cursors)
  ├─ Rendering .......... DirectX 8 calls → dx8wrapper dlopen → DXVK d3d8/d3d9 → Vulkan
  │                       (macOS/iOS add MoltenVK → Metal; Android has NATIVE Vulkan)
  ├─ Audio .............. OpenAL Soft 1.24.2 (FetchContent) + FFmpeg decode (replaces Miles)
  ├─ Video .............. FFmpeg 8.x (replaces Bink)
  ├─ Text ............... FreeType; fontconfig on Linux/macOS, bundled fonts/ dir on iOS
  └─ Online ............. GameSpy SDK; cross-platform MP broken (float determinism;
                          fdlibm scaffold exists behind SAGE_USE_DETERMINISTIC_MATH, default OFF)
```

## 2. Platform isolation is real (verified, not just claimed)

Guard-density sweep results:

- `GeneralsMD/.../GameLogic/` — **1** file with platform guards (out of hundreds)
- `GeneralsMD/.../GameClient/` — **2** files (ReplayMenu, PopupPlayerInfo)
- `Core/.../WW3D2/` (renderer) — **7** files, and only 4 that matter:
  `dx8wrapper.cpp` (DXVK load), `render2dsentence.{h,cpp}` (fonts),
  `dx8webbrowser.cpp` / `FramGrab.cpp` (stubbed periphery)
- `Core/.../WWMath/` — effectively platform-clean

**Everything Android must touch lives in:** `GeneralsMD/Code/Main/`,
`GeneralsMD/Code/GameEngineDevice/`, `Core/GameEngineDevice/`,
`GeneralsMD/Code/CompatLib/`, 4 files of `Core/.../WW3D2/`, and `cmake/`.

## 3. The seams a new platform plugs into

1. **Entry point**: `GeneralsMD/Code/Main/SDL3Main.cpp` (`#ifndef _WIN32`) —
   creates SDL window + Vulkan, sets env (DXVK_WSI_DRIVER etc.), injects
   `-xres/-yres` argv, then calls `GameMain()`.
2. **Factory**: `CreateGameEngine()` returns `SDL3GameEngine`, which overrides
   `createLocalFileSystem/ArchiveFileSystem/GameLogic/GameClient/ModuleFactory/
   ThingFactory/FunctionLexicon/Radar/ParticleSystemManager/AudioManager/WebBrowser`.
3. **Init**: `GameEngine::init()` builds ~40 subsystems in strict order from INI
   data (all paths `Data\INI\...` with backslashes — normalized in the FS layer).
4. **Loop**: `GameEngine::execute()` → `update()`: radar/audio/client → message
   propagation → logic gated by FramePacer accumulator (logic 30fps decoupled
   from render). Render happens inside `GameClient::update()` → `TheDisplay->draw()`.
5. **Files**: engine resolves ALL assets **CWD-relative**. `StdLocalFileSystem`
   (std::filesystem, backslash→slash, case-insensitive traversal fallback,
   asset-root fallback) + `StdBIGFileSystem` (.big archives; asset root resolved
   ENV `CNC_GENERALS_ZH_PATH` → Options.ini `[Paths]AssetPath` → registry-ini →
   exe dir → CWD; ZH additionally loads base-Generals data from `ZH_Generals/`
   or `../Generals/`).
6. **User data**: `GlobalData::BuildUserDataPathFromRegistry()` — Windows
   Documents / macOS `~/Library/Application Support/GeneralsX/GeneralsZH` /
   else XDG `~/.local/share/GeneralsX/GeneralsZH`. **No Android branch yet; the
   XDG branch depends on `$HOME`/`$XDG_DATA_HOME` which Android doesn't set.**
7. **"Registry"**: `System/registry.cpp` — env vars (`CNC_ZH_*`,
   `CNC_GENERALS_*`) → `registry.ini` → auto-detect (language via
   `<Lang>ZH.big` probe, install paths via relative-dir probes).

## 4. What the iOS port added (the template to replicate)

Complete engineering log: `docs/port/PORTING_PLAYBOOK.md`. Summary of the
mechanisms, all `TARGET_OS_IPHONE`-guarded:

- **SDL_main + owned lifecycle** (`SDL3Main.cpp`): `<SDL3/SDL_main.h>`, chdir to
  `<bundle>/GameData` (or Documents fallback), `DXVK_STATE_CACHE_PATH` → Caches,
  first-run `DefaultOptions.ini` seeding (forces `StaticGameLOD=High`,
  `TextureReduction=0` — the 2003 GPU auto-detect drops unknown GPUs to Low),
  capped/filtered stderr→file log sink, `SDL_WINDOW_HIGH_PIXEL_DENSITY`,
  `-xres/-yres` injection from `SDL_GetWindowSizeInPixels`,
  `SDL_HINT_TOUCH_MOUSE_EVENTS=0`.
- **Lifecycle pause** (`SDL3GameEngine.cpp`): `SDL_AddEventWatch` for
  WILL/DID_ENTER_BACKGROUND/FOREGROUND + FOCUS_LOST/GAINED → atomic flags gate
  `update()` to skip sim **and** present while backgrounded/inactive (GPU work
  around suspension = crash/hang).
- **Touch → mouse gesture state machine** (`SDL3GameEngine.cpp`, ~300 lines):
  `IDLE → PENDING → {tap | DRAGGING | LONGPRESSED | PAN}`. On finger-down send
  NOTHING; commit when the gesture identifies itself (tap = motion+LMB down+up
  at press point; drag past 8pt dead zone = LMB anchored at origin; second
  finger = RMB-drag pan at centroid, pinch = wheel every 6%; 600ms still =
  RMB click). Long-press must be **polled per frame** (stationary finger emits
  no events). Synthetic events MUST carry a valid `windowID` (coordinate
  scaling silently skips otherwise). Also drops `SDL_TOUCH_MOUSEID` mouse
  events (no double delivery). All synthesized through the same
  `SDL3Mouse::addSDLEvent` path real mice use — game code untouched.
- **DXVK on a phone**: local fork (`references/fbraz3-dxvk` @ 46a3bc01) +
  `Patches/dxvk-ios.patch` (bundle-relative MoltenVK dlopen paths; WSI
  `SDL_GetWindowSizeInPixels` + `SDL_PROC` table entry), meson cross file
  (`cmake/meson-arm64-ios-cross.ini.in`), sdl3.pc generated so meson resolves
  SDL3 not a silent SDL2 fallback.
- **Fonts without fontconfig** (`render2dsentence.cpp` iOS branch): normalize
  face name → `fonts/<name>.{ttf,otf,ttc}` under CWD → `fonts/arial.ttf`
  fallback. Liberation fonts staged renamed (arial.ttf etc.) by
  `scripts/build/ios/stage-fonts.sh`.
- **Packaging** (`scripts/build/ios/package-ios-zh.sh`): signed shell app →
  binary swap → embed dylibs → assets into bundle → re-sign. `--dev` skips the
  2.7GB asset copy.

## 5. Android port — raw material

### Reusable unchanged (Android defines `__linux__`; all `_UNIX`/`__linux__` paths apply)
- CompatLib entirely (threads/time/file/socket/gdi/com shims; `/proc/self/exe`)
- StdLocalFileSystem / StdBIGFileSystem (case-insensitive + asset-root fallbacks)
- OpenAL stack incl. the stream EOF/chirp fixes (openal-soft has OpenSL/AAudio
  backends), FFmpeg audio/video, FreeType rendering
- ALL GameLogic / GameClient / GameNetwork code
- Registry shim (env vars settable before engine start)
- The whole iOS touch gesture machine + lifecycle pause (widen the guard to
  `|| defined(__ANDROID__)`)

### Must be built new
1. **`android-vulkan` CMake preset** (mirror `ios-vulkan`):
   `CMAKE_SYSTEM_NAME=Android`, NDK toolchain, `ANDROID_ABI=arm64-v8a`,
   `VCPKG_TARGET_TRIPLET=arm64-android` + overlay triplet pinning min API
   (pattern: `cmake/triplets/arm64-ios.cmake` pins the deployment target).
   vcpkg deps: zlib glm gli freetype curl[ssl] ffmpeg(8.x override);
   fontconfig excluded (`!android`, like `!ios`).
2. **Game as `libmain.so`**: SDL3's Android model runs the game as a shared
   library loaded by `SDLActivity` — today the build produces an executable.
   Biggest single build-system delta vs iOS.
3. **DXVK cross-build for Android**: meson cross file from the NDK (mirror the
   iOS .ini.in), `-Ddxvk_native_wsi=sdl3` with sdl3.pc on PKG_CONFIG_PATH
   (verify `strings libdxvk_d3d9*.so | grep Sdl3WsiDriver` — the SDL2 fallback
   is silent). dlopen of `libvulkan.so` works natively on Android; the game's
   `LoadLibrary("libdxvk_d3d8.so")` Linux branch in `dx8wrapper.cpp` works if
   the .so ships in jniLibs (nativeLibraryDir is on the linker namespace path).
   Check upstream DXVK Android state first — Phase-0 research rule.
4. **`__ANDROID__` blocks in SDL3Main.cpp**: chdir to extracted-assets dir;
   `setenv("HOME", <internal files dir>)` (or add an Android branch in
   `GlobalData::BuildUserDataPathFromRegistry`); `DXVK_STATE_CACHE_PATH` →
   cache dir; Options.ini seeding; resolution injection reused as-is.
5. **Asset delivery**: .big archives can't be fopen'd inside an APK. Extract
   on first run to app storage (~2.7GB → external files dir), or sideload like
   the Linux flow. Steam fetch script (`scripts/get-assets.sh`) + the iOS
   exclusion list carry over. `ZH_Generals/` base-game data is REQUIRED.
6. **Gradle shell project** (analog of `ios/` XcodeGen stub): SDLActivity
   subclass, jniLibs = SDL3, SDL3_image, dxvk d3d8/d3d9, openal, gamespy,
   FFmpeg .so set, libmain.so. Landscape-locked manifest.
7. **Surface-lost handling**: Android destroys the EGL/Vulkan surface on
   background. The iOS pause gate covers most of it; a
   surface-recreate → `DX8Wrapper::Reset_Device()` path may be needed.

### Known hazards (each cost a debugging session on iOS/Linux)
- Silent DXVK SDL2-WSI fallback (verify artifacts with `strings`, never exit codes)
- Synthetic mouse events without valid `windowID` → hit-testing drifts
- `m_inputMovesAbsolute = TRUE` in SDL3Mouse::init is load-bearing
- 2003 GPU auto-detect → Low LOD on unknown GPU strings (seed Options.ini)
- Radar/shroud texture fallback needs per-caller alpha formats (W3DRadar)
- Memory: iPad sessions hit ~3GB resident; Android LMK will be stricter
- `_exit()` at end of main is deliberate (global pool dtors crash post-shutdown)
- Audio EOF: trust decoder-EOF AND buffer-queue agreement (chirp bug class)

## 6. Bug found during the read

`Dependencies/Utility/Utility/endian_compat.h`: the non-VC6 template helpers
`letohHelper<Type,4>` / `letohHelper<Type,8>` and the float/double
`letoh`/`betoh` specializations call **`le16toh`** where they should call
`le32toh`/`le64toh`. Identity on little-endian hosts (all current targets), so
harmless today — but wrong on big-endian and wrong as documentation of intent.
Full write-up: `docs/WORKDIR/audit/BUG_ENDIAN_COMPAT_LETOH_2026-07-06.md`.

## 7. Where the plan lives

Approved design spec: `docs/superpowers/specs/2026-07-06-android-port-design.md`.
Lessons from the read-through: `docs/WORKDIR/lessons/2026-07-LESSONS.md`.
