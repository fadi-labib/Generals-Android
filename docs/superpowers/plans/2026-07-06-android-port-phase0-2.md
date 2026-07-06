# Android Port — Phases 0–2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove the full non-graphics engine on Android hardware — research the renderer route (Phase 0), stand up the Android toolchain and app shell (Phase 1), and pass an on-device headless replay with correct CRC (Phase 2).

**Architecture:** The game compiles as `libmain.so` loaded by SDL3's `SDLActivity` in a thin Gradle shell app. All existing non-Windows code paths apply because Android defines `__linux__`. Rendering is deferred to the next plan (Phase 3+), whose route is decided by this plan's Phase 0 research.

**Tech Stack:** CMake presets + vcpkg (arm64-android overlay triplet), Android NDK r27 LTS, SDL3 3.4.2 (FetchContent), Gradle/AGP shell, adb/logcat for install + verification. Spec: `docs/superpowers/specs/2026-07-06-android-port-design.md`.

## Global Constraints

- Target: **arm64-v8a only**, `minSdkVersion 29`, `targetSdkVersion 29` (sideload only; targetSdk 29 keeps `requestLegacyExternalStorage` usable so assets live at `/sdcard/GeneralsZH`)
- Host: **Ubuntu primary**. Required env: `ANDROID_NDK_HOME` (NDK r27 LTS), `ANDROID_SDK_ROOT` (SDK with platform-tools + platforms;android-34 + build-tools), `VCPKG_ROOT`, JDK 17+, a connected arm64 device with USB debugging
- Every code change carries a `// GeneralsX @keyword FadiLabib 06/07/2026 <desc>` annotation (adjust date to the day you commit)
- Platform code ONLY in `GeneralsMD/Code/Main/`, `*/GameEngineDevice/`, `*/CompatLib/`, `cmake/`, `android/`, `scripts/build/android/` — NEVER in GameLogic/GameClient
- Commit messages: conventional commits, lower-case imperative (`build(android): add arm64 preset`), author `Fadi Labib <github@fadilabib.com>`, no AI co-author lines
- Verification is artifact-based: `readelf -h` (must show `AArch64`), `nm -u`, `strings` — never trust exit codes alone
- App id: `com.generalsx.generalszh` (override via Gradle property `GX_APP_ID`); no game assets ever enter git or the APK

---

### Task 1: Fix the endian_compat letoh bug (standalone, upstream-offerable)

**Files:**
- Modify: `Dependencies/Utility/Utility/endian_compat.h` (the `namespace Endian` template section, ~lines 195–215)

**Interfaces:**
- Produces: correct `letoh<T>()` for 4/8-byte types. No caller changes.

- [ ] **Step 1: Verify the defect is still present**

Run: `grep -n "le16toh(static_cast<SwapType32>\|le16toh(static_cast<SwapType64>\|le16toh(\*reinterpret_cast" Dependencies/Utility/Utility/endian_compat.h`
Expected: 4 hits (letohHelper<Type,4>, letohHelper<Type,8>, letohHelper<float,4>, letohHelper<double,8>). If 0 hits, someone already fixed it — skip to Step 4 and close the audit note.

- [ ] **Step 2: Apply the fix**

In `letohHelper<Type, 4>` and `letohHelper<float, 4>` replace `le16toh` with `le32toh`; in `letohHelper<Type, 8>` and `letohHelper<double, 8>` replace `le16toh` with `le64toh`. Add above the four-line group:

```cpp
// GeneralsX @bugfix FadiLabib 06/07/2026 letoh helpers called le16toh for 32/64-bit
// values (identity on little-endian hosts, wrong on big-endian). Use the width-correct macros.
```

- [ ] **Step 3: Verify no regression on the host build**

Run: `grep -c "le16toh" Dependencies/Utility/Utility/endian_compat.h` — expected: only the genuine 16-bit uses remain (2 in the template section: htole/betoh 2-byte helpers, plus the VC6 section).
Then: `cmake --preset linux64-deploy && cmake --build build/linux64-deploy --target z_generals -j$(nproc --ignore=1)` — expected: builds to completion (identity semantics unchanged on LE).

- [ ] **Step 4: Update the audit note status and commit**

In `docs/WORKDIR/audit/BUG_ENDIAN_COMPAT_LETOH_2026-07-06.md` change the `**Status:**` line to `Fixed in-tree (see commit); offer upstream to TheSuperHackers`.

```bash
git add Dependencies/Utility/Utility/endian_compat.h docs/WORKDIR/audit/BUG_ENDIAN_COMPAT_LETOH_2026-07-06.md
git commit -m "bugfix(compat): use width-correct le32toh/le64toh in letoh helpers"
```

---

### Task 2: Phase 0 research — DXVK-on-Android ecosystem survey

**Files:**
- Create: `docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md`

**Interfaces:**
- Produces: research doc sections `## 1. DXVK on Android — prior art` and `## 2. Driver landscape`. Task 4 writes the decision into the same doc.

- [ ] **Step 1: Create the doc skeleton**

```markdown
# Android Renderer Research (Phase 0)

Decides the Phase-3 renderer route for the Android port.
Spec: docs/superpowers/specs/2026-07-06-android-port-design.md

## 1. DXVK on Android — prior art
## 2. Driver landscape (stock Adreno/Mali vs Turnip)
## 3. BCn/DXT texture format support matrix
## 4. SDL3 on Android + precedent ports
## 5. DECISION
```

- [ ] **Step 2: Survey DXVK-Android prior art (web research)**

Research and record in section 1, each claim with a URL and, where possible, a commit/release artifact (playbook rule: verify claims against artifacts, not READMEs):
- dxvk-native upstream: does current DXVK master build for Android at all? Any `android` mentions in `meson.build` / issues / PRs?
- Winlator, Termux-box, Mobox lineage: which DXVK versions/forks do they ship for arm64 Android, and are those forks public? Note exact repos + branches.
- Any standalone "DXVK on Android without Wine" precedents (native arm64 games using dxvk-native, not x86 emulation).
- Record for each: DXVK version, WSI used, driver targeted (stock vs Turnip), evidence of it running.

- [ ] **Step 3: Survey the driver landscape (section 2)**

Record: Turnip (Mesa freedreno Vulkan) device coverage (Adreno 6xx/7xx), how it's loaded by an app (bundled `libvulkan_freedreno.so` + `VK_ICD_FILENAMES`-style loading vs system driver), legality/practicality of bundling Mesa in a GPL app; stock Qualcomm/ARM driver Vulkan 1.1/1.3 conformance on 2020+ flagships.

- [ ] **Step 4: Commit**

```bash
git add docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md
git commit -m "docs(android): renderer research - dxvk prior art and driver landscape"
```

---

### Task 3: Phase 0 research — BCn format support matrix

**Files:**
- Modify: `docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md` (section 3)

**Interfaces:**
- Consumes: doc from Task 2. Produces: filled BCn matrix that Task 4's decision cites.

- [ ] **Step 1: Build the format matrix from vulkan.gpuinfo.org**

The game's DDS assets use BC1/BC2/BC3 (DXT1/3/5); DXVK's D3D8 layer needs `VK_FORMAT_BC1_RGB_UNORM_BLOCK`, `BC1_RGBA_UNORM`, `BC2_UNORM`, `BC3_UNORM` with `SAMPLED_IMAGE` feature. On https://vulkan.gpuinfo.org query per format → Android, and record a table:

```markdown
| GPU / driver            | BC1 | BC2 | BC3 | Source |
|-------------------------|-----|-----|-----|--------|
| Adreno 7xx (stock)      | ?   | ?   | ?   | gpuinfo link |
| Adreno 6xx (stock)      | ?   | ?   | ?   | |
| Adreno 6xx/7xx (Turnip) | ?   | ?   | ?   | Mesa docs/MR link |
| Mali G7x/Immortalis     | ?   | ?   | ?   | |
| Samsung Xclipse (RDNA)  | ?   | ?   | ?   | |
```

- [ ] **Step 2: Record mitigation options below the table**

For every "no" cell, note the known mitigations with evidence links: Mesa/Turnip BCn emulation state; DXVK-side decode options if any; asset-side transcode cost estimate (count DDS files: `Data/…` in the retail assets ship thousands of DXT textures — note ballpark size increase if decompressed).

- [ ] **Step 3: Also record the user's actual device**

Run: `adb shell getprop ro.product.model ro.soc.model` (device connected) and `adb shell cmd gpu vkjson > /tmp/vkjson.txt 2>/dev/null || true` — if `vkjson` works, grep it for `BC1`/`textureCompressionBC`; record the result as the ground-truth row of the matrix.

- [ ] **Step 4: Commit**

```bash
git add docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md
git commit -m "docs(android): renderer research - BCn support matrix"
```

---

### Task 4: Phase 0 research — SDL3 precedents + DECISION (gate)

**Files:**
- Modify: `docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md` (sections 4, 5)
- Possibly modify: `docs/superpowers/specs/2026-07-06-android-port-design.md` (only if the decision pivots the spec's Phase-3 assumptions)

**Interfaces:**
- Produces: `## 5. DECISION` naming exactly one renderer route: `stock-driver` | `require-turnip` | `asset-transcode` (or `no-go`, which halts after Phase 2). The Phase 3+ plan consumes this.

- [ ] **Step 1: Fill section 4**

Record: SDL3 Android backport status (SDLActivity + SDL_main model in 3.4.x, known Android bugs), and 2–3 precedent native arm64 SDL3(+Vulkan) Android game ports with links.

- [ ] **Step 2: Write the decision**

In section 5, state the chosen route, the evidence lines it rests on (cite table rows/links from sections 1–3), the fallback order (matching the spec's pivot ranking), and what Phase 3's DXVK build step must do differently (if anything) vs the spec's default.

- [ ] **Step 3: Reconcile the spec**

If the decision contradicts a spec assumption, edit the spec's "Pivot points" / Phase 3 wording to match and note the change inline (`> Amended 2026-07-XX after Phase 0 research`). If it doesn't, add one line to the spec's Phase 0: `Decision: <route> — see ANDROID_RENDERER_RESEARCH_2026-07.md §5`.

- [ ] **Step 4: Commit — PHASE 0 GATE**

```bash
git add docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md docs/superpowers/specs/2026-07-06-android-port-design.md
git commit -m "docs(android): renderer route decision (phase 0 gate)"
```

Gate check: section 5 names exactly one route and cites at least one artifact (not a README claim) per load-bearing conclusion. **Stop and review with the project owner before Phase 1.**

---

### Task 5: Android environment check script

**Files:**
- Create: `scripts/build/android/check-android-env.sh`

**Interfaces:**
- Produces: `check-android-env.sh` (exit 0 = environment ready). Called by every later Android script.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Verify the Android build environment (Ubuntu primary host).
#
# Usage: ./scripts/build/android/check-android-env.sh
# Environment:
#   ANDROID_NDK_HOME   NDK r27 LTS root (contains build/cmake/android.toolchain.cmake)
#   ANDROID_SDK_ROOT   SDK root (platform-tools/adb, build-tools, platforms)
#   VCPKG_ROOT         full vcpkg clone
set -eu

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${ANDROID_NDK_HOME:-}" ]] || fail "ANDROID_NDK_HOME not set (install NDK r27 LTS via sdkmanager 'ndk;27.2.12479018')"
[[ -f "${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" ]] || fail "NDK toolchain file missing under ANDROID_NDK_HOME"
grep -qs "Pkg.Revision = 27" "${ANDROID_NDK_HOME}/source.properties" || echo "WARNING: NDK is not r27 LTS ($(grep Pkg.Revision "${ANDROID_NDK_HOME}/source.properties" 2>/dev/null || echo unknown))"

[[ -n "${ANDROID_SDK_ROOT:-}" ]] || fail "ANDROID_SDK_ROOT not set"
command -v adb >/dev/null || [[ -x "${ANDROID_SDK_ROOT}/platform-tools/adb" ]] || fail "adb not found (SDK platform-tools)"

[[ -n "${VCPKG_ROOT:-}" ]] || fail "VCPKG_ROOT not set (full clone, not shallow)"
[[ -f "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" ]] || fail "vcpkg toolchain missing under VCPKG_ROOT"

command -v cmake >/dev/null || fail "cmake not found"
command -v ninja >/dev/null || fail "ninja not found"
command -v java >/dev/null || fail "java (JDK 17+) not found"

ADB="$(command -v adb || echo "${ANDROID_SDK_ROOT}/platform-tools/adb")"
if ! "${ADB}" get-state >/dev/null 2>&1; then
    echo "WARNING: no device connected (needed for install/run tasks, not for builds)"
fi

echo "Android environment OK"
```

- [ ] **Step 2: Verify it**

Run: `chmod +x scripts/build/android/check-android-env.sh && ./scripts/build/android/check-android-env.sh`
Expected: `Android environment OK` (fix your env until it passes; the WARNINGs are acceptable).

- [ ] **Step 3: Commit**

```bash
git add scripts/build/android/check-android-env.sh
git commit -m "build(android): environment check script"
```

---

### Task 6: Toolchain — triplet, vcpkg platforms, preset, SDL3 PNG fix (gate: configure succeeds)

**Files:**
- Create: `cmake/triplets/arm64-android.cmake`
- Modify: `vcpkg.json` (fontconfig + ffmpeg platform expressions)
- Modify: `CMakePresets.json` (add `android-vulkan` configure preset after `ios-vulkan`)
- Modify: `cmake/sdl3.cmake` (Android branch for libpng)

**Interfaces:**
- Produces: `cmake --preset android-vulkan` configures. Preset name `android-vulkan`, build dir `build/android-vulkan`, triplet `arm64-android` — all later tasks use these exact names.

- [ ] **Step 1: Write the overlay triplet**

`cmake/triplets/arm64-android.cmake`:

```cmake
# Overlay triplet: pin the Android API level so vcpkg-built static libs match
# the engine's ANDROID_PLATFORM (pattern: arm64-ios.cmake pins the iOS target).
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION 29)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
```

- [ ] **Step 2: Adjust vcpkg.json platforms**

Change the fontconfig entry's platform from `"!windows & !ios"` to `"!windows & !ios & !android"` (Android uses the bundled-font path, no fontconfig). Change the ffmpeg entry's platform from `"ios"` to `"ios | android"` (no system FFmpeg on Android; Linux keeps using the system one).

- [ ] **Step 3: Add the android-vulkan preset**

Insert into `CMakePresets.json` `configurePresets` after `ios-vulkan`:

```json
{
    "name": "android-vulkan",
    "displayName": "Android (Vulkan + SDL3 + OpenAL) arm64-v8a Device",
    "inherits": "default-vcpkg",
    "generator": "Ninja",
    "binaryDir": "${sourceDir}/build/${presetName}",
    "description": "Android port: arm64-v8a, API 29+, game built as libmain.so for SDL3's SDLActivity. Requires ANDROID_NDK_HOME (r27 LTS).",
    "cacheVariables": {
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",
        "CMAKE_BUILD_TYPE": "RelWithDebInfo",
        "VCPKG_TARGET_TRIPLET": "arm64-android",
        "VCPKG_OVERLAY_TRIPLETS": "${sourceDir}/cmake/triplets",
        "VCPKG_CHAINLOAD_TOOLCHAIN_FILE": "$env{ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake",
        "ANDROID_ABI": "arm64-v8a",
        "ANDROID_PLATFORM": "android-29",
        "SAGE_USE_DX8": "OFF",
        "SAGE_USE_SDL3": "ON",
        "SAGE_USE_OPENAL": "ON",
        "SAGE_USE_GLM": "ON",
        "SAGE_UPDATE_CHECK": "OFF",
        "RTS_CRASHDUMP_ENABLE": "OFF",
        "RTS_BUILD_OPTION_FFMPEG": "ON",
        "RTS_BUILD_OPTION_SAGE_PATCH": "OFF",
        "RTS_BUILD_GENERALS": "OFF",
        "RTS_BUILD_CORE_TOOLS": "OFF",
        "RTS_BUILD_ZEROHOUR_TOOLS": "OFF",
        "RTS_BUILD_ZEROHOUR_EXTRAS": "OFF"
    },
    "environment": {
        "PKG_CONFIG_PATH": "${sourceDir}/build/android-vulkan/vcpkg_installed/arm64-android/lib/pkgconfig"
    }
}
```

- [ ] **Step 4: Android branch in cmake/sdl3.cmake**

The current logic runs `find_library(PNG …)` + `find_package(PNG REQUIRED)` on every non-Apple platform — there is no libpng on Android. Change the platform chain (currently `if(NOT APPLE) … elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS") … else() …`) so Android is checked FIRST:

```cmake
    if(ANDROID)
        # GeneralsX @build FadiLabib 06/07/2026 Android has no system libpng and
        # SDL3_image rejects vcpkg's static one. Disable the libpng backend —
        # PNG still decodes via SDL3_image's stb backend (same approach as iOS).
        set(SDLIMAGE_PNG_LIBPNG OFF CACHE BOOL "No libpng on Android; stb decodes PNG" FORCE)
        set(SDLIMAGE_PNG_SHARED OFF CACHE BOOL "No shared libpng on Android" FORCE)
    elseif(NOT APPLE)
        ... (existing Linux find_library/find_package block unchanged)
```

(Keep the existing iOS `elseif` and macOS `else` branches as they are.)

- [ ] **Step 5: Run configure — the task's test**

Run: `./scripts/build/android/check-android-env.sh && cmake --preset android-vulkan 2>&1 | tee /tmp/android-configure.log`
Expected: vcpkg builds zlib/glm/gli/freetype/curl/ffmpeg for arm64-android (first run: tens of minutes), then CMake configures to `-- Configuring done` / `-- Generating done`.
If configure fails INSIDE a vcpkg port: read the port's build log it names; NDK path/API mismatches are env problems, not code. If it fails in project CMake with a missing FFMPEG package: verify `build/android-vulkan/vcpkg_installed/arm64-android/lib/pkgconfig/libavcodec.pc` exists — if it does, the PKG_CONFIG_PATH env in the preset has a typo.

- [ ] **Step 6: Commit**

```bash
git add cmake/triplets/arm64-android.cmake vcpkg.json CMakePresets.json cmake/sdl3.cmake
git commit -m "build(android): arm64-android triplet, android-vulkan preset, vcpkg platforms, SDL3 png handling"
```

---

### Task 7: libmain.so target + SDL_main + minimal __ANDROID__ entry block

**Files:**
- Modify: `GeneralsMD/Code/Main/CMakeLists.txt:1-10`
- Modify: `GeneralsMD/Code/Main/SDL3Main.cpp` (SDL_main include guard ~line 37; new `__ANDROID__` block at top of `main()`)

**Interfaces:**
- Consumes: preset from Task 6.
- Produces: CMake target `z_generals` emitting `libmain.so` on Android; entry expects assets at `/sdcard/GeneralsZH` (constant `GX_ANDROID_ASSET_DIR`) and sets `HOME` to SDL's internal storage path. Tasks 8–11 rely on the library name `main` and that asset path.

- [ ] **Step 1: Make the target a shared library on Android**

Replace lines 1–10 of `GeneralsMD/Code/Main/CMakeLists.txt`:

```cmake
# GeneralsX @build FadiLabib 06/07/2026 Android: SDL3's SDLActivity loads the game
# as a shared library named libmain.so and calls its SDL_main. Everything else
# stays an executable.
if(ANDROID)
    add_library(z_generals SHARED)
    set_target_properties(z_generals PROPERTIES OUTPUT_NAME "main")
else()
add_executable(z_generals WIN32)

# Use a binary name that doesn't conflict with original game.
# GeneralsX @build BenderAI 15/02/2026 Linux branding update
if("${CMAKE_SYSTEM}" MATCHES "Windows")
    set_target_properties(z_generals PROPERTIES OUTPUT_NAME "generalszh${RTS_BUILD_OUTPUT_SUFFIX}")
else()
    # GeneralsX @build BenderAI 15/02/2026 Linux branding update
    set_target_properties(z_generals PROPERTIES OUTPUT_NAME GeneralsXZH)
endif()
endif()
```

- [ ] **Step 2: Widen the SDL_main include guard in SDL3Main.cpp**

The include block at ~line 37 currently reads `#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE` around `#include <SDL3/SDL_main.h>`. Change the condition and comment:

```cpp
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || defined(__ANDROID__)
// GeneralsX @build FadiLabib 06/07/2026 On iOS and Android, SDL owns the app
// lifecycle: SDL_main.h renames main() to SDL_main, which SDL's bootstrap
// (UIApplicationMain / SDLActivity JNI) invokes.
#include <SDL3/SDL_main.h>
```

(Keep the iOS-only sub-includes — `<sys/stat.h>` etc. — inside their existing guard; add `#include <sys/stat.h>` under a new `#elif defined(__ANDROID__)` if the compiler asks for it in Step 4.)

- [ ] **Step 3: Add the Android entry block at the top of main()**

Directly after the `__argc/__argv` assignment in `main()` (before the iOS `#if` block), insert:

```cpp
#if defined(__ANDROID__)
	// GeneralsX @feature FadiLabib 06/07/2026 Android bootstrap.
	// The engine resolves ALL game data relative to the working directory
	// (see StdLocalFileSystem); assets are pushed to /sdcard/GeneralsZH by
	// scripts/build/android/push-assets-android.sh (targetSdk 29 +
	// requestLegacyExternalStorage keeps that path readable).
	// HOME must exist because GlobalData's user-data path and the registry
	// shim derive from it on the POSIX branch; Android doesn't set it.
	{
		static const char *GX_ANDROID_ASSET_DIR = "/sdcard/GeneralsZH";
		const char *internal = SDL_GetAndroidInternalStoragePath();
		if (internal != nullptr) {
			setenv("HOME", internal, 0);
			setenv("XDG_DATA_HOME", internal, 0);
		}
		if (chdir(GX_ANDROID_ASSET_DIR) != 0) {
			fprintf(stderr, "FATAL: chdir(%s) failed: %s — push assets first "
			        "(scripts/build/android/push-assets-android.sh)\n",
			        GX_ANDROID_ASSET_DIR, strerror(errno));
			return 1;
		}
		fprintf(stderr, "INFO: Android working directory: %s, HOME=%s\n",
		        GX_ANDROID_ASSET_DIR, internal ? internal : "<unset>");
	}
#endif
```

Add `#include <cerrno>` next to the existing system includes if not already present for Android (`cerrno` is currently iOS-guarded).

- [ ] **Step 4: Attempt the build — expect failures, that's the next task's input**

Run: `cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1) 2>&1 | tee /tmp/android-build-1.log`
Expected at this stage: compile errors in engine libraries (Task 8 fixes them). What must NOT appear: errors inside `GeneralsMD/Code/Main/*` itself — fix any of those now.

- [ ] **Step 5: Commit**

```bash
git add GeneralsMD/Code/Main/CMakeLists.txt GeneralsMD/Code/Main/SDL3Main.cpp
git commit -m "feat(android): build game as libmain.so with SDL_main and android bootstrap"
```

---

### Task 8: Compile-fix sweep until libmain.so links (gate: artifact checks pass)

**Files (known fixes — residuals follow the same pattern):**
- Modify: `Core/Libraries/Source/WWVegas/WW3D2/CMakeLists.txt` (SAGE_USE_FREETYPE / fontconfig guards)
- Modify: `Core/Libraries/Source/WWVegas/WW3D2/render2dsentence.cpp` (+`render2dsentence.h` if it carries the same guard)
- Modify: any `CMakeLists.txt`/`*.cmake` with `PLATFORM_ID` generator expressions missing `Android`
- Possibly modify: files under `Core/`, `GeneralsMD/Code/GameEngine*/`, `GeneralsMD/Code/CompatLib/` with `#ifdef` chains that treat "not Apple, not Windows" as "desktop Linux"

**Interfaces:**
- Consumes: Task 7's target. Produces: `build/android-vulkan/GeneralsMD/libmain.so`, arm64, with no unresolved non-libc symbols.

- [ ] **Step 1: Audit PLATFORM_ID generator expressions (iOS lesson §4 of the playbook)**

Run: `grep -rn "PLATFORM_ID" --include="CMakeLists.txt" --include="*.cmake" Core/ GeneralsMD/ cmake/ | grep -v Android`
For every hit where Linux/Darwin/iOS get a feature Android also needs (notably `SAGE_USE_FREETYPE` in `Core/.../WW3D2/CMakeLists.txt`), add `Android` to the list: `$<$<PLATFORM_ID:Linux,Darwin,iOS,Android>:SAGE_USE_FREETYPE>`. Annotate each edit.

- [ ] **Step 2: Fontconfig must not be referenced on Android**

In `Core/Libraries/Source/WWVegas/WW3D2/CMakeLists.txt`, find the fontconfig `find_package`/link block (it is already skipped for iOS) and extend the skip to Android (`if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT ANDROID)` or the file's existing idiom).
In `render2dsentence.cpp`, the font locator is selected by `#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE` (bundled-`fonts/` dir) vs fontconfig. Widen the bundled branch:

```cpp
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || defined(__ANDROID__)
// GeneralsX @build FadiLabib 06/07/2026 Android, like iOS, has no fontconfig and
// no user-visible system fonts: resolve faces from the fonts/ dir under CWD
// (Liberation set staged by the packaging flow, arial.ttf fallback).
```

(The `#else // !TARGET_OS_IPHONE` comment and the closing `#endif` comment must be updated to match.)

- [ ] **Step 3: Build → fix → repeat**

Run: `cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1) 2>&1 | tee /tmp/android-build-N.log`
For each residual error apply the repo's established pattern (see `docs/WORKDIR/lessons/LESSON-platform-guards-apple-vs-win32.md`):
- "not Windows" code assuming glibc/desktop-Linux facilities Android lacks (`<execinfo.h>`, `glob.h` is present on Android but `pthread_cancel` is NOT — `TerminateThread` in `CompatLib/Source/thread_compat.cpp` will need `#ifdef __ANDROID__ return -1; // not supported #else pthread_cancel #endif`)
- whole-function `#ifdef` replacement over line-by-line guards
- platform code only in the allowed directories; if an error points into GameLogic/GameClient, the fix belongs in a compat header, not there.
Keep a running list of every file touched + one-line reason in the commit body.

- [ ] **Step 4: Artifact verification — the gate**

```bash
readelf -h build/android-vulkan/GeneralsMD/libmain.so | grep -E "Class|Machine"
# Expected: ELF64, AArch64
nm -D --undefined-only build/android-vulkan/GeneralsMD/libmain.so | grep -vE "@|__android|android_|AAsset|__cxa|__emutls|mem|str|pthread_|std::|operator" | head -40
# Expected: only libc/liblog/libSDL3/libopenal/libav* symbols — nothing from our own libs
grep -c "SDL_main" <(nm -D build/android-vulkan/GeneralsMD/libmain.so)
# Expected: >= 1 (exported entry point)
```

- [ ] **Step 5: Commit**

```bash
git add -A Core/ GeneralsMD/ cmake/
git commit -m "build(android): compile fixes - freetype/fontconfig guards, platform sweeps; libmain.so links"
```

---

### Task 9: Gradle shell app + packaging script (PHASE 1 GATE: app launches with SDL initialized)

**Files:**
- Create: `android/settings.gradle`, `android/build.gradle`, `android/gradle.properties`, `android/app/build.gradle`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/java/com/generalsx/generalszh/GeneralsXZHActivity.java`, `android/app/src/main/res/values/strings.xml`, `android/.gitignore`
- Create: `scripts/build/android/package-android-zh.sh`

**Interfaces:**
- Consumes: `libmain.so` (Task 8), SDL3/SDL3_image/openal/gamespy `.so`s from `build/android-vulkan/_deps/*-build/` and `build/android-vulkan/`.
- Produces: installable debug APK `android/app/build/outputs/apk/debug/app-debug.apk`; activity `com.generalsx.generalszh/.GeneralsXZHActivity` accepting an intent string extra `args`. Tasks 10–11 use both.

- [ ] **Step 1: Write the Gradle project**

`android/settings.gradle`:
```groovy
rootProject.name = "GeneralsXZH"
include ':app'
```

`android/build.gradle`:
```groovy
plugins { id 'com.android.application' version '8.5.2' apply false }
```

`android/gradle.properties`:
```properties
android.useAndroidX=true
org.gradle.jvmargs=-Xmx2g
```

`android/app/build.gradle`:
```groovy
plugins { id 'com.android.application' }

android {
    namespace 'com.generalsx.generalszh'
    compileSdk 34
    defaultConfig {
        applicationId project.findProperty('GX_APP_ID') ?: 'com.generalsx.generalszh'
        minSdk 29
        targetSdk 29   // sideload-only: keeps requestLegacyExternalStorage effective
        versionCode 1
        versionName "1.04"
        ndk { abiFilters 'arm64-v8a' }
    }
    buildTypes {
        debug { debuggable true }
    }
    sourceSets.main {
        jniLibs.srcDirs = ['jniLibs']       // populated by package-android-zh.sh
        java.srcDirs = ['src/main/java', 'sdl-java']  // sdl-java copied from SDL3 source
    }
}
```

`android/app/src/main/AndroidManifest.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-feature android:name="android.hardware.vulkan.version" android:version="0x401000" android:required="true" />
    <application
        android:label="@string/app_name"
        android:requestLegacyExternalStorage="true"
        android:hasCode="true">
        <activity
            android:name=".GeneralsXZHActivity"
            android:exported="true"
            android:screenOrientation="landscape"
            android:configChanges="orientation|screenSize|keyboard|keyboardHidden|navigation|uiMode"
            android:launchMode="singleInstance">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

`android/app/src/main/res/values/strings.xml`:
```xml
<resources><string name="app_name">Generals ZH</string></resources>
```

`android/app/src/main/java/com/generalsx/generalszh/GeneralsXZHActivity.java`:
```java
package com.generalsx.generalszh;

import org.libsdl.app.SDLActivity;

/**
 * GeneralsX @feature FadiLabib 06/07/2026 Thin SDLActivity shell.
 * getArguments() forwards an intent string extra "args" as engine argv,
 * enabling headless runs: adb shell am start -n <pkg>/.GeneralsXZHActivity
 *   --es args "-headless -replay 00000000.rep"
 */
public class GeneralsXZHActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[] { "SDL3", "main" };
    }

    @Override
    protected String[] getArguments() {
        String args = getIntent() != null ? getIntent().getStringExtra("args") : null;
        if (args == null || args.trim().isEmpty()) {
            return new String[0];
        }
        return args.trim().split("\\s+");
    }
}
```

`android/.gitignore`:
```
app/jniLibs/
app/sdl-java/
app/build/
.gradle/
local.properties
gradle/
gradlew*
```

- [ ] **Step 2: Write the packaging script**

`scripts/build/android/package-android-zh.sh`:
```bash
#!/usr/bin/env bash
# Package the Android build of Zero Hour into a debug APK and optionally install it.
#
# Flow: verify artifacts -> copy .so's into jniLibs -> copy SDL3 Java glue ->
#       gradle assembleDebug -> optional adb install.
# Usage: ./scripts/build/android/package-android-zh.sh [--install]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/android-vulkan"
ANDROID_DIR="${PROJECT_ROOT}/android"
JNILIBS="${ANDROID_DIR}/app/jniLibs/arm64-v8a"
SDL_JAVA_SRC="${BUILD_DIR}/_deps/sdl3-src/android-project/app/src/main/java"
SDL_JAVA_DST="${ANDROID_DIR}/app/sdl-java"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

"${SCRIPT_DIR}/check-android-env.sh"

GAME_LIB="${BUILD_DIR}/GeneralsMD/libmain.so"
[[ -f "${GAME_LIB}" ]] || { echo "ERROR: ${GAME_LIB} missing - build android-vulkan first" >&2; exit 1; }
# Artifact check, not exit-code trust: right arch, entry point exported.
readelf -h "${GAME_LIB}" | grep -q AArch64 || { echo "ERROR: libmain.so is not arm64" >&2; exit 1; }
nm -D "${GAME_LIB}" | grep -q "SDL_main" || { echo "ERROR: libmain.so does not export SDL_main" >&2; exit 1; }

rm -rf "${JNILIBS}" "${SDL_JAVA_DST}"
mkdir -p "${JNILIBS}"
copy_lib() {  # copy_lib <glob> <required:1|0>
    local matched=0 f
    for f in $1; do [[ -f "$f" ]] && { cp "$f" "${JNILIBS}/"; matched=1; echo "  embedded $(basename "$f")"; }; done
    [[ $matched -eq 1 || $2 -eq 0 ]] || { echo "ERROR: required lib not found: $1" >&2; exit 1; }
}
copy_lib "${GAME_LIB}" 1
copy_lib "${BUILD_DIR}/_deps/sdl3-build/libSDL3.so*" 1
copy_lib "${BUILD_DIR}/_deps/sdl3_image-build/libSDL3_image.so*" 1
copy_lib "${BUILD_DIR}/_deps/openal_soft-build/libopenal.so*" 1
copy_lib "${BUILD_DIR}/libgamespy.so" 0
# Versioned .so names (libSDL3.so.0) are not loadable from an APK: keep bare .so only.
for f in "${JNILIBS}"/*.so.*; do [[ -e "$f" ]] && rm "$f"; done

mkdir -p "${SDL_JAVA_DST}"
cp -R "${SDL_JAVA_SRC}/org" "${SDL_JAVA_DST}/"
echo "  copied SDL3 Java glue"

( cd "${ANDROID_DIR}" && gradle assembleDebug --console=plain )
APK="${ANDROID_DIR}/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "${APK}" ]] || { echo "ERROR: APK not produced" >&2; exit 1; }
echo "==> APK ready: ${APK}"

if [[ ${DO_INSTALL} -eq 1 ]]; then
    adb install -r "${APK}"
    PKG="$(grep -oP "applicationId project.findProperty\('GX_APP_ID'\) \?: '\K[^']+" "${ANDROID_DIR}/app/build.gradle")"
    adb shell pm grant "${PKG}" android.permission.READ_EXTERNAL_STORAGE || true
    adb shell pm grant "${PKG}" android.permission.WRITE_EXTERNAL_STORAGE || true
    echo "==> Installed ${PKG} (storage permissions granted)"
fi
```

Note: SDL3's `SDL_SHARED=ON` (already forced in `cmake/sdl3.cmake`) yields `libSDL3.so`; if only versioned names exist in `_deps/sdl3-build/`, the unversioned symlink is there too — `cp` dereferences it.

- [ ] **Step 3: Build the APK and install — the PHASE 1 GATE**

Run:
```bash
chmod +x scripts/build/android/package-android-zh.sh
./scripts/build/android/package-android-zh.sh --install
adb logcat -c && adb shell am start -n com.generalsx.generalszh/.GeneralsXZHActivity
sleep 5 && adb logcat -d | grep -E "SDL|GeneralsX|FATAL|GameMain" | head -40
```
Expected: SDLActivity starts, `libmain.so` loads, our banner appears (`Command & Conquer Generals: Zero Hour (Linux)` from SDL3Main) and then the Android bootstrap `FATAL: chdir(/sdcard/GeneralsZH) failed` (assets not pushed yet) — **that exact failure is the gate**: it proves Java shell → SDL → SDL_main → our code, crashing only at the expected, documented point.

- [ ] **Step 4: Commit**

```bash
git add android/ scripts/build/android/package-android-zh.sh
git commit -m "feat(android): gradle shell app, SDLActivity subclass, packaging script (phase 1 gate)"
```

---

### Task 10: Asset push script

**Files:**
- Create: `scripts/build/android/push-assets-android.sh`

**Interfaces:**
- Consumes: a PC-side asset dir (`~/GeneralsX/GeneralsZH` by default — same layout the Linux/macOS deploys use, produced by `scripts/get-assets.sh`), the fonts staged by `scripts/build/ios/stage-fonts.sh` (`~/GeneralsX/ios-staging/fonts`).
- Produces: `/sdcard/GeneralsZH/` populated on-device (`*.big`, `Data/`, `ZH_Generals/`, `fonts/`). Task 11 and every future phase depend on this path.

- [ ] **Step 1: Write the script**

```bash
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
```

- [ ] **Step 2: Run it — the task's test**

Run: `chmod +x scripts/build/android/push-assets-android.sh && ./scripts/build/android/push-assets-android.sh`
Expected: push completes; verification lists `.big` files, three fonts, and `ZH_Generals` (no WARNING).

- [ ] **Step 3: Commit**

```bash
git add scripts/build/android/push-assets-android.sh
git commit -m "build(android): asset push script (adb, filtered, fonts included)"
```

---

### Task 11: Headless replay on-device (PHASE 2 GATE)

**Files:**
- Create: `scripts/build/android/run-headless-replay.sh`
- Possibly modify: whatever the run exposes (fix-forward, same rules as Task 8 Step 3)

**Interfaces:**
- Consumes: installed APK (Task 9), on-device assets (Task 10), a replay: copy one from `GeneralsReplays/` (repo, used by CI) into the device's replay dir.
- Produces: a repeatable on-device replay harness — the standing regression check for all later phases.

- [ ] **Step 1: Write the harness script**

```bash
#!/usr/bin/env bash
# Run a headless replay on the connected Android device and report pass/fail.
#
# Usage: ./scripts/build/android/run-headless-replay.sh <replay.rep> [timeout_s]
set -euo pipefail

REP="${1:?usage: run-headless-replay.sh <replay.rep> [timeout_s]}"
TIMEOUT="${2:-600}"
PKG="com.generalsx.generalszh"
# The engine looks for replays under the user-data dir:
# HOME=<internal storage> -> XDG_DATA_HOME -> GeneralsX/GeneralsZH/Replays
DEV_REPLAY_DIR="/sdcard/GeneralsZH/Replays"   # start simple: CLI path is passed absolute

[[ -f "${REP}" ]] || { echo "ERROR: ${REP} not found (see GeneralsReplays/)" >&2; exit 1; }
adb get-state >/dev/null

adb shell mkdir -p "${DEV_REPLAY_DIR}"
adb push "${REP}" "${DEV_REPLAY_DIR}/test.rep" >/dev/null

adb logcat -c
adb shell am force-stop "${PKG}"
adb shell am start -n "${PKG}/.GeneralsXZHActivity" \
    --es args "-headless -replay ${DEV_REPLAY_DIR}/test.rep"

echo "==> Waiting for completion (timeout ${TIMEOUT}s)…"
END=$(( $(date +%s) + TIMEOUT ))
RESULT=""
while [[ $(date +%s) -lt ${END} ]]; do
    # SDL routes stdout/stderr to logcat (tag SDL/APP); our engine prints
    # "GameMain() returned with code N" on completion (SDL3Main.cpp).
    if adb logcat -d | grep -q "GameMain() returned with code"; then
        RESULT="$(adb logcat -d | grep "GameMain() returned with code" | tail -1)"
        break
    fi
    if ! adb shell pidof "${PKG}" >/dev/null 2>&1 && adb logcat -d | grep -qE "FATAL|SIGSEGV|beginning of crash"; then
        RESULT="CRASHED"
        break
    fi
    sleep 5
done

adb logcat -d > /tmp/android-replay-logcat.txt
echo "==> Full log: /tmp/android-replay-logcat.txt"
case "${RESULT}" in
    *"code 0"*) echo "PASS: ${RESULT}"; exit 0 ;;
    "")         echo "FAIL: timeout"; exit 2 ;;
    *)          echo "FAIL: ${RESULT}"; exit 1 ;;
esac
```

- [ ] **Step 2: First run — expect surprises, fix forward**

Run: `chmod +x scripts/build/android/run-headless-replay.sh && ./scripts/build/android/run-headless-replay.sh GeneralsReplays/$(ls GeneralsReplays | grep -m1 '\.rep$')`
(Pick any `.rep` from the repo's `GeneralsReplays/`; check that folder for the actual layout — replays may sit in subfolders with their maps.)

Likely first failures and their fixes (apply Task 8's rules):
- **stdout/stderr not visible in logcat**: SDL redirects them only when `SDL_HINT_LOG` … if the marker never appears while the app runs and exits, wire stderr to logcat: in the Android block of `SDL3Main.cpp`, dup stderr through a pipe-to-`__android_log_write` thread, or simpler — replace the completion detection by writing a result file: after `exitcode = GameMain();` add an `#ifdef __ANDROID__` block writing `/sdcard/GeneralsZH/last-run-exitcode.txt`, and have the harness poll that file instead. Choose ONE mechanism, implement it fully, and keep it (later phases reuse this harness).
- **Replay map missing**: the replay needs its map — push the map dir alongside per `TESTING.md` (`Maps/` under user data or asset dir); the repo's `GeneralsReplays/` folders bundle required maps.
- **Headless still touching SDL video**: the `m_headless` guard already exists in `SDL3Main.cpp`/`SDL3GameEngine::init` (Linux CI uses it); if Android trips a different path, guard it the same way.

- [ ] **Step 3: The PHASE 2 GATE**

Run the harness until: `PASS: … GameMain() returned with code 0`, and `grep -iE "replay|simulat" /tmp/android-replay-logcat.txt` shows the replay simulation ran to its final frame (not an instant exit — compare wall time to the same replay on `linux64-deploy`: `~/GeneralsX/GeneralsZH/run.sh -headless -replay <same.rep>`; the Android run must be the same order of magnitude, and the logged final frame count must match).

- [ ] **Step 4: Commit**

```bash
git add scripts/build/android/run-headless-replay.sh GeneralsMD/Code/Main/SDL3Main.cpp
git commit -m "feat(android): on-device headless replay harness (phase 2 gate)"
```

---

### Task 12: Documentation + handoff to the Phase 3+ plan

**Files:**
- Create: `docs/BUILD/ANDROID.md`
- Create: `docs/DEV_BLOG/2026-07-DIARY.md` (or append if it exists by then)
- Modify: `docs/WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md` (status note)

**Interfaces:**
- Produces: reproducible instructions; the Phase 3+ plan's starting state.

- [ ] **Step 1: Write docs/BUILD/ANDROID.md**

Cover, with exact commands verified against what you actually ran: prerequisites (NDK r27 LTS via sdkmanager, SDK, JDK 17, vcpkg full clone, env vars), configure/build (`cmake --preset android-vulkan`, `--target z_generals`), packaging (`package-android-zh.sh --install`), assets (`get-assets.sh` → `push-assets-android.sh`), headless verification (`run-headless-replay.sh`), current status table (Phases 0–2 ✅, rendering ⏳ pending Phase 3 plan), and the renderer-route decision link.

- [ ] **Step 2: Dev blog entry (repo convention)**

Add a dated entry to `docs/DEV_BLOG/2026-07-DIARY.md` summarizing: what was done (phases 0–2), root causes of the interesting fixes found in Tasks 8/11 (each with file paths), validation performed. Follow the existing diary entry format (see `2026-06-DIARY.md`).

- [ ] **Step 3: Status note + commit**

Append to the findings doc §7: `Phases 0–2 executed — see docs/BUILD/ANDROID.md. Phase 3+ plan: to be written from ANDROID_RENDERER_RESEARCH_2026-07.md §5.`

```bash
git add docs/BUILD/ANDROID.md docs/DEV_BLOG/2026-07-DIARY.md docs/WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md
git commit -m "docs(android): build guide, dev blog, phase 0-2 status"
```

- [ ] **Step 4: Rerun the full gate stack once, clean**

```bash
./scripts/build/android/check-android-env.sh
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
./scripts/build/android/package-android-zh.sh --install
./scripts/build/android/run-headless-replay.sh GeneralsReplays/<the replay used in Task 11>
```
Expected: PASS end-to-end from a warm tree. This is the plan's exit state; the Phase 3+ plan (renderer bring-up per the Phase 0 decision, touch/lifecycle, audio/video, parity polish) is written next, against this verified baseline.
