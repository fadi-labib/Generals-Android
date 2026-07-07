---
description: The full story of porting C&C Generals Zero Hour to Android in under 24 hours — the plan, the walls, the 2am root causes, and what shipped.
---

# The Android Journey

!!! abstract "What this is"
    How a 2003 DirectX 8 RTS went from "never ran on Android" to a public APK in
    about a day of wall-clock work — told honestly, walls and all. The companion
    page, [Bugs & Lessons](BUGS_AND_LESSONS.md), catalogs every defect found.

## Day 0 — the audit and the bet (July 6)

The port started with a codebase audit, not code. The engine had already been carried
to macOS/Linux (fbraz3/GeneralsX) and iOS/iPadOS (Ammaar Reshi) — the question was
what Android would *reuse* versus *rediscover*. The audit produced a 7-phase plan and
one decisive early finding:

**The renderer bet.** DXVK 2.6 requires Vulkan 1.3. The Galaxy Tab S7+'s stock
Qualcomm driver exposes **Vulkan 1.1** — and, contradicting published claims, no BCn
texture support either (we tested; the research doc's `[CLAIM]` died on real
hardware). That forced the route: bundle **Mesa Turnip** (open-source Adreno driver,
Vulkan 1.3) inside the APK and load it *rootlessly* via **libadrenotools**. No root,
no system modification — the driver rides along with the game.

## Phases 0–2 — prove the engine before the pixels (July 6)

Toolchain (NDK r27, Gradle, vcpkg overlay triplet), a Gradle/SDLActivity shell app,
and packaging came first — the APK launched `SDL_main` on three devices the same day.

Then the move that paid for itself all week: **run the whole game headless before
attempting a single frame**. The engine's `-headless -replay` mode simulates a full
match — INI rules, maps, pathfinding, economy — with no renderer. A macOS-recorded
replay *diverged* on Android (bionic vs Apple libm: transcendental functions drift
across hundreds of frames — documented, expected, not a bug). So the harness taught
the engine to **record its own AI-vs-AI skirmish on-device** and play it back:
1,500 frames, bit-exact, exit 0. The simulation was proven before graphics existed.

## The renderer night (July 6, evening → July 7, ~2 am)

Phase 3 was one long night of walls, each with a name:

1. **The invisible error wall.** DXVK cross-compiled, then failed with empty error
   messages: DXVK statically linked libc++, so its exceptions carried private RTTI
   and vanished into `catch(...)` across the `.so` boundary. Fix: one shared
   `libc++_shared.so` for everything. Every later root cause was findable because of
   this fix.
2. **The Vulkan 1.1 wall.** DXVK enumerated the stock driver and refused. Turnip via
   adrenotools went in: the app stages the bundled driver into its private directory,
   exports the loader contract, and DXVK's patched loader dlopens it. Logcat printed
   `Turnip Adreno (TM) 650 … Vulkan 1.3` for the first time around 1 am.
3. **The two-loaders wall.** SDL loads its *own* copy of the system Vulkan loader;
   handing DXVK's Turnip `VkInstance` to SDL's `SDL_Vulkan_CreateSurface` corrupts
   dispatch. The patched WSI takes only the raw `ANativeWindow*` from SDL and creates
   the surface through DXVK's own loader.
4. **The crash cascade.** With a device alive, the game began dying in
   `Pathfinder::reset()`, then bridges, then smudges — all the same disease:
   *the 2003 codebase silently assumes `new` returns zeroed memory* (desktop builds
   route allocation through a pool that memsets; bionic `malloc` is dirty). The cure
   was systemic — Android's global `new` now uses `calloc` — plus explicit fixes for
   the worst offenders, which are latent bugs on **every** platform
   ([offered upstream](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad/issues/10)).

By ~2 am the app *survived* — and the session notes said "it works." It didn't, quite.

## The black screen (July 7, 02:00 – 02:30)

The game ran — menus loading, UI objects created, music playing in the logs — behind
a **pure black screen**. Every Vulkan surface creation failed with
`VK_ERROR_NATIVE_WINDOW_IN_USE_KHR`, forever.

The hunt that followed is the single best story of the port:

- An `ANativeWindow` accepts **exactly one producer connection**. Someone was holding
  it. Who?
- Counting `Device properties:` blocks in the DXVK logs showed **two D3D9 devices**
  created 30 ms apart. The engine's display-init retry loop builds a first device
  whose depth-format default (`D3DFMT_D32`, chosen blindly when mode-matching fails)
  the driver rejects — but that doomed device's swapchain had *already created its
  surface and connected the window*, and the failure path leaked the connection. The
  surviving retry device could never connect. Black screen, forever, by design.
- The fix was confirmed **without a rebuild**: DXVK reads `dxvk.conf` from its working
  directory, and the game's cwd is `/sdcard/GeneralsZH` — so
  `adb push dxvk.conf` with `d3d9.deferSurfaceCreation = True` (create the surface at
  first *present*, so only the surviving device ever touches the window) went to the
  device, the app restarted, and…

**02:24: the Skirmish menu, rendered, at native 2800×1752.** Eleven minutes later, a
live match: command center, dozer, minimap, 59 FPS. The fix became one `setenv` line.

## The morning after — sound, fingers, lifecycle (July 7, 02:30 – 03:00)

- **The game was silent**, and the reason is a warning to every porter:
  `__ANDROID__` also defines `__linux__`, so a desktop-Linux audio workaround
  (`ALSOFT_DRIVERS=pulse,alsa,…` — none of which exist on Android) had been forcing
  OpenAL to the null backend. One guard change and OpenSL ES sang.
- **Touch** came from the iOS port's gesture translator — adopted by literally
  widening an `#if TARGET_OS_IPHONE` to include `__ANDROID__`. That inheritance is
  why this port took a day.
- **Lifecycle**: the iOS background render-pause covered Android's
  destroyed-window-after-HOME case too. HOME → resume survived, same process.

## The touch deep-dive (July 7, ~10:00 – 12:00)

Real usage exposed three feel problems, and fixing them produced the port's most
methodical debugging session: **instrumenting all six stages** of the tap pipeline
(gesture translator → SDL3Mouse → Mouse stream → WindowXlat → window routing →
button gadget) and reading what the device said instead of theorizing.

The trace found a beauty: the main menu **eats the first tap after boot**. Desktop
hides the menu until the mouse *moves* 20 px; on touch, the first tap's hover-motion
triggers the reveal transition, and the tap's deferred click lands mid-animation
while the buttons are still transition-hidden — hit-testing skips hidden windows, so
the click dies silently on the parent. The engine even contained its own
commented-out auto-show code, revived for touch platforms.

Two more physics-level fixes landed the same session: two-finger **pan and pinch now
mode-lock** (running both at once meant every pan leaked zoom ticks and every pinch
drifted the camera), and gesture thresholds became **physical (3 mm, DPI-scaled)**
instead of 8 px — which is 0.7 mm on this panel, small enough that fingertip jitter
turned taps into accidental drag-boxes. All three improvements
[flow back to iOS](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad/issues/11).

## One that fought back

Not every fix survived contact: an attempt to clean up the "wasteful" two-device boot
(default to `D24S8` depth, one device) *mechanically worked* — and rendered the 3D
world **solid black**. Isolation testing proved the 16-bit-**color** back buffer of
the retry path is currently the only configuration that draws on this Turnip/Adreno
path. The "bug" is load-bearing; the mystery is
[tracked](https://github.com/fadi-labib/Generals-Android/issues/8), and the lesson —
*verify on-device before believing a clean-looking change* — is written into the
regression checklist.

## Shipping day (July 7)

The branch merged after a CI run validated the shared-code changes on macOS, Linux,
and Android. Then, in one afternoon: replay tests taught to skip gracefully on forks
without the encrypted assets bundle; the docs got a real site with navigation; the
bugs went [upstream](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad/issues/10)
as three gift-wrapped issues; and
[**v0.1.0-alpha**](https://github.com/fadi-labib/Generals-Android/releases/tag/android-v0.1.0-alpha)
— an 80 MB APK, no game assets, no root required — became the first public build.

## Why it was fast (credit, again)

Under 24 hours is a headline, not a boast: nearly every hard problem had been solved
once before, by [Ammaar Reshi's iOS port](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad)
and the [GeneralsX lineage](https://github.com/fbraz3/GeneralsX) — and, crucially,
**written down**. The iOS Porting Playbook turned this port's debugging from
archaeology into lookups. This journey page and the
[Bugs & Lessons ledger](BUGS_AND_LESSONS.md) exist to return that favor to whoever
ports this engine to the next platform.
