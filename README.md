# C&C Generals: Zero Hour — Native on Android

[![APK](https://img.shields.io/github/v/release/fadi-labib/Generals-Android?include_prereleases&label=APK&color=3DDC84&logo=android&logoColor=white)](https://github.com/fadi-labib/Generals-Android/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/fadi-labib/Generals-Android/ci.yml?branch=main&label=CI)](https://github.com/fadi-labib/Generals-Android/actions)
[![Docs](https://img.shields.io/badge/docs-website-blue?logo=readthedocs&logoColor=white)](https://fadi-labib.github.io/Generals-Android/)
[![License: GPL v3](https://img.shields.io/badge/license-GPL%20v3-blue)](LICENSE.md)
[![Discussions](https://img.shields.io/github/discussions/fadi-labib/Generals-Android?color=8B5CF6)](https://github.com/fadi-labib/Generals-Android/discussions)

**The real 2003 engine, compiled for arm64, playing skirmish matches on a tablet.**
No emulation: DirectX 8 → [DXVK](https://github.com/doitsujin/dxvk) → Vulkan 1.3 on a
bundled [Mesa Turnip](https://docs.mesa3d.org/drivers/freedreno.html) driver, loaded
rootlessly with [libadrenotools](https://github.com/bylaws/libadrenotools). RTS touch
controls: tap-select, drag-box, long-press right-click, two-finger pan, pinch zoom.

![Zero Hour skirmish on a Galaxy Tab S7+](docs/BUILD/screenshots/android-tab-s7plus-ingame.png)

Ported in **under 24 hours** as a **human + AI collaboration** — possible only because
[Ammaar Reshi's iOS/iPadOS port](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)
and the [GeneralsX lineage](#credits) had already carried this engine across the hard
miles. **No game assets included** — bring your own Zero Hour
([Steam](https://store.steampowered.com/app/2732960/), ~$5 on sale).

## Get it

1. **Device**: arm64 Android with a Qualcomm **Adreno 6xx/7xx** GPU
   (others: [#9](https://github.com/fadi-labib/Generals-Android/issues/9)).
2. **APK**: [Releases](https://github.com/fadi-labib/Generals-Android/releases) →
   sideload ([Samsung gotcha](https://fadi-labib.github.io/Generals-Android/BUILD/ANDROID/#samsung-sideload-gotcha)).
3. **Assets**: push your own game files —
   [how](https://fadi-labib.github.io/Generals-Android/BUILD/ANDROID/#assets).

More questions? **[FAQ](https://fadi-labib.github.io/Generals-Android/FAQ/)**.

## Status

| | |
|---|---|
| Menus, shell map, skirmish vs AI | ✅ ~30–60 FPS at 2800×1752 |
| Touch, audio, HOME→resume | ✅ |
| Campaign / Challenge / video | ❓ [#12](https://github.com/fadi-labib/Generals-Android/issues/12) |
| Non-Adreno GPUs (Xclipse, Mali) | ❌ [#9](https://github.com/fadi-labib/Generals-Android/issues/9) |

Full list: [Known issues & remaining work](https://fadi-labib.github.io/Generals-Android/BUILD/ANDROID/#known-issues-and-remaining-work).

## Build from source

```sh
git clone https://github.com/fadi-labib/Generals-Android.git && cd Generals-Android
git submodule update --init --recursive references/fbraz3-dxvk references/libadrenotools
cmake --preset android-vulkan
cmake --build build/android-vulkan --target z_generals -j$(nproc --ignore=1)
./scripts/build/android/build-adrenotools.sh && ./scripts/build/android/fetch-turnip.sh
./scripts/build/android/package-android-zh.sh --install
```

Full guide (toolchain, debugging toolbox, traps):
**[Android build guide](https://fadi-labib.github.io/Generals-Android/BUILD/ANDROID/)**.

## The port in one paragraph

Five mechanics had to be discovered the hard way, each breaking the port until fixed:
Vulkan 1.3 on a Vulkan 1.1 device (bundle Turnip, load it rootlessly), one Vulkan
loader instead of two (SDL and DXVK each bring their own), the one-producer
`ANativeWindow` rule (the engine's device-retry loop leaked it → black screen), shared
libc++ across `.so` boundaries (or C++ exceptions vanish), and a zero-initialized heap
(the 2003 code silently assumes it).

**The full story** — the renderer night, the 2 am black-screen hunt, the touch
deep-dive, and 17 cataloged bugs with root causes:
**[The Android Journey](https://fadi-labib.github.io/Generals-Android/journey/ANDROID_JOURNEY/)**
· **[Bugs & Lessons](https://fadi-labib.github.io/Generals-Android/journey/BUGS_AND_LESSONS/)**
· [rendering pipeline](https://fadi-labib.github.io/Generals-Android/BUILD/ANDROID/#rendering-pipeline-phase-3)
· [touch controls](https://fadi-labib.github.io/Generals-Android/port/TOUCH_CONTROLS/).

## Contributing

Human or AI, the door is open — the repo is deliberately **AI-first**:

- Agents start at [AGENTS.md](AGENTS.md); humans at [CONTRIBUTING.md](CONTRIBUTING.md).
- Entry points: [`good first issue`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) ·
  [`ai-ready`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3Aai-ready) ·
  [`help wanted`](https://github.com/fadi-labib/Generals-Android/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).
- Device testing reports are as valuable as code — especially non-Samsung Adreno.

## Credits

This project is the newest link in a chain, and says so gladly — the speed was
borrowed from years of work by:

- **Westwood / EA Pacific** — the game; **EA** — the GPL v3 source release.
- **[TheSuperHackers](https://github.com/TheSuperHackers/GeneralsGameCode)** — build
  modernization and cross-platform groundwork, with FFmpeg/OpenAL backends by
  [feliwir](https://github.com/feliwir).
- **[Fighter19's Unix port](https://github.com/Fighter19/CnC_Generals_Zero_Hour)** —
  SDL3 platform management, 64-bit fixes, the DXVK approach.
- **[fbraz3/GeneralsX](https://github.com/fbraz3/GeneralsX)** — the macOS/Linux port:
  compatibility layer, vcpkg build system, DXVK integration.
- **[Ammaar Reshi's iOS/iPadOS port](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)**
  — the direct parent and the single biggest reason this took a day, not months:
  the touch→mouse translator (adopted wholesale, then
  [evolved here](https://fadi-labib.github.io/Generals-Android/port/TOUCH_CONTROLS/) —
  improvements flow back), the lifecycle handling, the DXVK-on-mobile cross-build
  methodology, and the porting playbook that turned debugging into lookups. Want this
  on Mac/iPhone/iPad? **Go there.**
- **Mesa Turnip · libadrenotools ·
  [K11MCH1's drivers](https://github.com/K11MCH1/AdrenoToolsDrivers) · DXVK · SDL ·
  OpenAL Soft · FFmpeg** — the load-bearing walls.

Engine code **GPL v3**; game assets not included, not licensed here.
