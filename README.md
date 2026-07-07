# Command & Conquer Generals: Zero Hour — Native on Android

[![APK](https://img.shields.io/github/v/release/fadi-labib/Generals-Android?include_prereleases&label=APK&color=3DDC84&logo=android&logoColor=white)](https://github.com/fadi-labib/Generals-Android/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/fadi-labib/Generals-Android/ci.yml?branch=main&label=CI)](https://github.com/fadi-labib/Generals-Android/actions)
[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-blue)](LICENSE.md)
[![Platform](https://img.shields.io/badge/device-arm64%20·%20Adreno%206xx%2F7xx-orange)](docs/BUILD/ANDROID.md#devices-profiled)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)
[![Discussions](https://img.shields.io/github/discussions/fadi-labib/Generals-Android?color=8B5CF6)](https://github.com/fadi-labib/Generals-Android/discussions)
[![Docs](https://img.shields.io/badge/docs-fadi--labib.github.io-blue?logo=readthedocs&logoColor=white)](https://fadi-labib.github.io/Generals-Android/)

**The real 2003 engine, compiled for arm64, playing skirmish matches on a tablet.**
No emulation, no streaming: EA's GPL v3 source release, cross-built for Android,
rendering DirectX 8 → [DXVK](https://github.com/doitsujin/dxvk) → Vulkan 1.3 on a
bundled [Mesa Turnip](https://docs.mesa3d.org/drivers/freedreno.html) driver, loaded
rootlessly with [libadrenotools](https://github.com/bylaws/libadrenotools) — because
the stock Adreno driver only speaks Vulkan 1.1. Touch controls built for RTS:
tap-select, drag-box, long-press right-click, two-finger pan, pinch zoom.

![Zero Hour skirmish on a Galaxy Tab S7+](docs/BUILD/screenshots/android-tab-s7plus-ingame.png)

Ported in **under 24 hours** — a speed that was only possible because
[Ammaar Reshi's iOS/iPadOS port](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)
and the whole [GeneralsX lineage](#the-porting-story) had already carried this engine
across the hard miles. This repo is the Android chapter of their story.

This port is a **human + AI collaboration**, and proudly so: the C++, the
cross-builds, and the device debugging were done by
[Claude Code](https://claude.com/claude-code), directed and playtested by a human
who described symptoms, made every decision, and owned the result. The AI can't do
this without human know-how; the human can't do it at this speed without the AI.
The repo is built to keep working that way — see [Contributing](#contributing).

**No game assets are included or distributed.** You need your own copy of Zero Hour
([Steam](https://store.steampowered.com/app/2732960/), ~$5 on sale).

## Get it

1. **Device**: arm64 Android with a Qualcomm **Adreno 6xx/7xx** GPU (tested: Galaxy
   Tab S7+ / Adreno 650). Non-Adreno GPUs (Exynos/Xclipse, Mali) don't work yet —
   [#9](https://github.com/fadi-labib/Generals-Android/issues/9).
2. **APK**: grab the latest from [Releases](https://github.com/fadi-labib/Generals-Android/releases)
   and sideload it (Samsung users: see the
   [sideload gotcha](docs/BUILD/ANDROID.md#samsung-sideload-gotcha)).
3. **Assets**: push your own game files to the device —
   [`scripts/build/android/push-assets-android.sh`](scripts/build/android/push-assets-android.sh),
   or see [Assets](docs/BUILD/ANDROID.md#assets) for the manual route.

## What works, what doesn't

| | Status |
|---|---|
| Main menu + animated 3D shell map | ✅ |
| Skirmish: lobby → live match, HUD, game clock | ✅ ~30–60 FPS at 2800×1752 |
| Touch controls (single-tap, drag-box, long-press, pan, pinch) | ✅ |
| Audio (OpenAL → OpenSL ES) | ✅ |
| Lifecycle: HOME → resume, background render-pause | ✅ |
| Campaign / Generals Challenge / video playback | ❓ untested — [#12](https://github.com/fadi-labib/Generals-Android/issues/12) |
| Non-Adreno devices (Xclipse, Mali) | ❌ — [#9](https://github.com/fadi-labib/Generals-Android/issues/9) |
| Two-device boot workaround (cosmetic, boot-time) | ⚠️ load-bearing — [#8](https://github.com/fadi-labib/Generals-Android/issues/8) |

The honest, detailed list lives in
[Known Issues & Remaining Work](docs/BUILD/ANDROID.md#known-issues-and-remaining-work).

## The porting story

### What we inherited

This project is the newest link in a chain, and says so gladly. The Android port came
together in **under a day** — and that speed is almost entirely borrowed. The genuinely
hard work, spread over years by the people below, was already done: making a 2003
Windows / DirectX 8 game build and run on modern 64-bit ARM *at all* — the compatibility
layer, the SDL3 platform port, the DXVK renderer path, the OpenAL and FFmpeg backends.
Android didn't have to solve any of that. It mostly had to teach an already-working
machine about one more platform. From the lineage came the foundation this port stands on:

- **EA's GPL v3 source release** — the engine itself.
- **[TheSuperHackers/GeneralsGameCode](https://github.com/TheSuperHackers/GeneralsGameCode)** —
  build modernization (VC6 → modern toolchains) and cross-platform groundwork,
  including the FFmpeg video and OpenAL audio backends by
  [feliwir](https://github.com/feliwir).
- **[Fighter19's Unix port](https://github.com/Fighter19/CnC_Generals_Zero_Hour)** —
  SDL3 platform management, 64-bit fixes, and the DXVK renderer approach this
  pipeline descends from.
- **[fbraz3/GeneralsX](https://github.com/fbraz3/GeneralsX)** — the macOS/Linux port:
  the platform compatibility layer, vcpkg build system, and DXVK integration this
  repo cross-compiles.
- **[Ammaar Reshi's iOS/iPadOS port](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)**
  — the direct parent, and the single biggest reason this port took a day instead of
  months. Nearly every hard problem Android faced, his port had already solved once:
  the touch→mouse gesture translator (tap-defer, drag-box, long-press, pan, pinch —
  reused **verbatim**, Android widened an `#if` guard), the app-lifecycle render
  pause, the DXVK-on-mobile cross-build methodology (meson cross-file + patch
  workflow that `dxvk-android.patch` copies wholesale), the fontconfig-free font
  staging, and — maybe most valuable of all — the
  [Porting Playbook](docs/port/PORTING_PLAYBOOK.md): a written record of every
  failure mode and root cause, which turned Android's debugging nights from
  archaeology into lookups. Want this game on a Mac, iPhone, or iPad? **Go there** —
  that's their project and their story.

### What we built here

The Android renderer did not exist, and five load-bearing mechanics had to be
discovered the hard way — each one broke the port until fixed
([full detail](docs/BUILD/ANDROID.md#rendering-pipeline-phase-3)):

1. **Vulkan 1.3 on a 1.1 device** — bundle Mesa Turnip in the APK and load it
   rootlessly via libadrenotools, no root, no system driver replacement.
2. **One Vulkan loader, not two** — SDL and DXVK each load their own Vulkan;
   handing DXVK's `VkInstance` to SDL's loader corrupts surface creation. The
   patched WSI creates the Android surface from DXVK's own loader.
3. **An `ANativeWindow` accepts exactly one producer** — the engine's
   device-retry loop leaked the window connection and every later device failed
   forever (`VK_ERROR_NATIVE_WINDOW_IN_USE_KHR`, black screen). Fix: deferred
   surface creation.
4. **Shared libc++ across .so boundaries** — or DXVK's C++ exceptions vanish into
   `catch(...)` with their RTTI, swallowing the real error message.
5. **Zero-initialized heap** — the 2003 codebase silently relies on the desktop
   pool allocator's memset; Bionic malloc is dirty, so Android allocates with
   `calloc`.

Plus everything around them: the arm64-android DXVK meson cross-build driven from
cmake, the vcpkg overlay triplet, the Gradle/SDLActivity shell app and packaging
pipeline, OpenSL audio bring-up, touch gesture enablement and tuning for a
2800×1752 panel, CI (compile-check on every PR) and tag-triggered APK releases.

### What flowed back

Bugs found on Android that were latent everywhere: uninitialized-member crashes
(`Pathfinder`, `W3DBridgeBuffer`, `W3DSmudgeManager`), null back-buffer guards, an
`__ANDROID__`-implies-`__linux__` audio trap, and a stderr log pump that filters
~85% of boot spam. Fixes are offered upstream.

### What's next

The roadmap is the issue tracker — labels mark the entry points:
[`good first issue`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) ·
[`ai-ready`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3Aai-ready) ·
[`help wanted`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).
Highlights: gesture tuning in real matches
([#11](https://github.com/fadi-labib/Generals-Android/issues/11)), performance
headroom ([#13](https://github.com/fadi-labib/Generals-Android/issues/13)), campaign
and video testing ([#12](https://github.com/fadi-labib/Generals-Android/issues/12)),
the Turnip device-lifecycle mystery
([#8](https://github.com/fadi-labib/Generals-Android/issues/8)), and the big one —
non-Adreno devices ([#9](https://github.com/fadi-labib/Generals-Android/issues/9)).

## Build from source

Ubuntu host, Android NDK r27 + SDK, Gradle 8.9, JDK 21, vcpkg. Full guide with
troubleshooting, device setup, and the debugging toolbox:
**[docs/BUILD/ANDROID.md](docs/BUILD/ANDROID.md)**.

```sh
git clone https://github.com/fadi-labib/Generals-Android.git && cd Generals-Android
git submodule update --init --recursive references/fbraz3-dxvk references/libadrenotools
cmake --preset android-vulkan
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
./scripts/build/android/build-adrenotools.sh    # rootless Vulkan-driver loader
./scripts/build/android/fetch-turnip.sh         # pinned Mesa Turnip (Vulkan 1.3)
./scripts/build/android/package-android-zh.sh --install
./scripts/build/android/push-assets-android.sh  # your own game files → /sdcard/GeneralsZH
```

## Porting a 2003 Windows game yourself?

The lineage wrote it down so you don't have to rediscover it:

- [docs/port/PORTING_PLAYBOOK.md](docs/port/PORTING_PLAYBOOK.md) — the complete
  engineering log of the iOS port this one descends from: every failure mode, root
  cause, fix.
- [docs/port/PORTING_PATTERNS.md](docs/port/PORTING_PATTERNS.md) — the generalized
  methodology.
- [docs/BUILD/ANDROID.md](docs/BUILD/ANDROID.md) — this port as a case study:
  pipeline, five mechanics, debugging toolbox, traps, regression checklist.
- [docs/port/TOUCH_CONTROLS.md](docs/port/TOUCH_CONTROLS.md) — mouse-driven RTS →
  touch, every design decision with its reason.

## Contributing

Human or AI agent, the door is open — this repo is deliberately **AI-first**:

- **Agents start at [AGENTS.md](AGENTS.md)**; issues labeled
  [`ai-ready`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3Aai-ready)
  carry enough context to work without a clarification round-trip.
- **Humans start at [CONTRIBUTING.md](CONTRIBUTING.md)**; testing reports from real
  devices are as valuable as code — especially non-Samsung Adreno devices.
- Every PR declares its AI involvement and shows verification evidence — the
  [PR template](.github/PULL_REQUEST_TEMPLATE.md) includes the on-device
  [regression checklist](docs/BUILD/ANDROID.md#regression-checklist-definition-of-still-works).
- Questions and show-and-tell:
  [Discussions](https://github.com/fadi-labib/Generals-Android/discussions).

## Lineage & credits

Full credit chain, because none of this starts from zero: **Westwood / EA Pacific**
(the game), **EA** (the GPL v3 source release),
**[TheSuperHackers](https://github.com/TheSuperHackers/GeneralsGameCode)** (community
mainline), **[feliwir](https://github.com/feliwir)** (FFmpeg/OpenAL backends,
[OpenSAGE](https://github.com/OpenSAGE/OpenSAGE)),
**[Fighter19](https://github.com/Fighter19/CnC_Generals_Zero_Hour)** (Unix port),
**[fbraz3/GeneralsX](https://github.com/fbraz3/GeneralsX)** (macOS/Linux port),
**[ammaarreshi/Generals-Mac-iOS-iPad](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)**
(iOS/iPadOS port, this repo's direct parent), **[Mesa
Turnip](https://docs.mesa3d.org/drivers/freedreno.html)** /
**[libadrenotools](https://github.com/bylaws/libadrenotools)** /
**[K11MCH1's driver builds](https://github.com/K11MCH1/AdrenoToolsDrivers)** (the
open Vulkan 1.3 stack that makes the Android renderer possible), and **DXVK, SDL,
OpenAL Soft, FFmpeg** — the load-bearing walls.

Engine code **GPL v3** (EA's source release → the chain above → this repo). Game
assets: not included, not licensed here.
