# Android Port — Phase 3 (Renderer) Implementation Plan

> Autonomous execution (owner unavailable). Route ratified Phase 0: **require-turnip**. Goal: **main menu renders at native resolution on the Tab S7+ (Adreno 650)**. Spec: docs/superpowers/specs/2026-07-06-android-port-design.md §Phase 3.

**Goal:** Bring up the D3D8→DXVK→Vulkan renderer on Android arm64 so the game displays, on the Adreno 650 tablet, via a bundled Mesa Turnip driver (stock Adreno 650 lacks BCn — empirically confirmed).

**Critical unknown (make-or-break, do FIRST):** nobody has cross-built dxvk-native for bionic/NDK. Task 1 is a feasibility spike; everything else depends on its outcome.

## Global Constraints
- arm64-v8a, API 29; platform code only in Main/, GameEngineDevice/, CompatLib/, cmake/, android/, scripts/build/android/, references/fbraz3-dxvk (the DXVK fork)
- Every edit `// GeneralsX @keyword FadiLabib 06/07/2026`; conventional commits; author Fadi Labib <github@fadilabib.com>; no AI co-author lines
- Verify artifacts not exit codes: `strings libdxvk_d3d9*.so | grep Sdl3WsiDriver`; `readelf -h` AArch64; on-device `driverID == VK_DRIVER_ID_MESA_TURNIP` before trusting BCn
- Non-Android platforms must be unaffected (additive/guarded)
- Device: Tab S7+ (R52NC03AXPW, Adreno 650). Push progress to origin/feature/android-phase3-renderer after each task.

---

### Task 1: DXVK arm64-Android cross-build spike (feasibility gate)
Cross-build dxvk-native d3d8+d3d9 for arm64-android using a meson cross file generated from the NDK (mirror cmake/meson-arm64-ios-cross.ini.in). Source: references/fbraz3-dxvk (submodule) or upstream dxvk-native — whichever builds. Must resolve SDL3 via pkg-config so WSI is Sdl3WsiDriver (not silent SDL2). **Gate:** libdxvk_d3d8.so + libdxvk_d3d9.so exist, `readelf -h` shows AArch64, `strings` shows Sdl3WsiDriver. If dxvk-native cannot compile against bionic/NDK after real effort, STOP with the specific compile blockers documented (that is the pivot-decision evidence).

### Task 2: Wire DXVK Android build into cmake/dx8.cmake
Add an Android branch to cmake/dx8.cmake (ExternalProject meson build, like the iOS/macOS path) producing the two .so's in the build tree, with the meson cross file generated from $ANDROID_NDK_HOME + the SDL3 pkg-config from the FetchContent build. Gate: `cmake --build` produces the dxvk .so's as part of the normal android-vulkan build.

### Task 3: Package DXVK .so's + verify dx8wrapper loads them
package-android-zh.sh copies libdxvk_d3d8.so + libdxvk_d3d9.so into jniLibs. Confirm dx8wrapper.cpp's existing Linux `LoadLibrary("libdxvk_d3d8.so")` branch resolves them from the APK nativeLibraryDir on Android (add an __ANDROID__ path only if bare-name dlopen fails). Gate: on-device, the dlopen succeeds (logcat: no "libdxvk_d3d8.so not found"), DX8Wrapper::Init gets past LoadLibrary.

### Task 4: Bundle Mesa Turnip + libadrenotools driver load
Fetch a Turnip arm64 Android build (libvulkan_freedreno.so + meta.json) and integrate libadrenotools to load it as the Vulkan driver before DXVK creates its VkInstance (hook in SDL3Main.cpp Android block or the DXVK vulkan_loader). Bundle the driver in the APK. Gate: on-device, `driverID == VK_DRIVER_ID_MESA_TURNIP` at device creation AND textureCompressionBC==true (logged). If libadrenotools integration is too invasive, fall back to documenting stock-driver behavior (no BCn → textures fail) as evidence.

### Task 5: Vulkan/WSI bring-up → device creation
Get SDL3's Vulkan surface + DXVK's D3D8 device creation working on Android (the -xres/-yres injection and SDL_WINDOW flags may need Android tweaks; DXVK config dxvk.conf shipped in assets). Gate: DX8Wrapper::Create_Device succeeds on-device (logcat: Direct3DCreate8 non-null, CreateDevice OK).

### Task 6: Main menu renders (PHASE 3 GATE)
Everything together: launch non-headless on the Tab S7+, the shell menu (Menus/MainMenu.wnd) draws. Seed Options.ini LOD=High. Gate: a screenshot (`adb exec-out screencap -p`) shows the main menu rendered, not a black screen or crash. This is the phase's true halfway-point milestone.

### Task 7: Docs + push
Update docs/BUILD/ANDROID.md renderer section + dev blog; push branch. If Phase 3 gate reached, note Phase 4 (touch/lifecycle) is next.

---
**Autonomy note:** Each task is dispatched to a subagent (Opus for the DXVK/driver work, Sonnet for packaging/docs), task-reviewed, committed, pushed. Where a decision would normally need the owner, pick the option best supported by the Phase 0 research and document it in the ledger. Stop only on a genuine hard block (e.g. dxvk-native fundamentally won't build for Android and needs upstream work beyond this scope) — and if so, leave the branch pushed with a clear BLOCKED writeup.
