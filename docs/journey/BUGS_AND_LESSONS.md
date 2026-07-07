---
description: Every bug the Android port found — symptom, root cause, fix, upstream status — plus the transferable lessons for porting old engines to new platforms.
---

# Bugs & Lessons

!!! abstract "What this is"
    The complete defect ledger of the Android port, and what each one teaches.
    Narrative version: [The Android Journey](ANDROID_JOURNEY.md).

## The ledger

Engine bugs — latent on **all** platforms, unmasked by Android's allocator
([offered upstream → #10](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad/issues/10)):

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 1 | SIGSEGV cascades all over `GameEngine::init` | The 2003 codebase silently assumes `new` returns **zeroed** memory (desktop pool allocator memsets; bionic `malloc` is dirty) | Android global `new` → `calloc`; the systemic cure for the class |
| 2 | Crash in `Pathfinder::reset()` at startup | Ctor never initializes `m_blockOfMapCells`; `reset()` `delete[]`s it before nulling | Init-list `nullptr` |
| 3 | Crash in `W3DBridge::clearBridge()` | `W3DBridgeBuffer` ctor calls `clearAllBridges()` with `m_numBridges` uninitialized → out-of-bounds `REF_PTR_RELEASE` loop | Zero it first |
| 4 | Crash in `W3DSmudgeManager` init | Constructor entirely empty; `ReleaseResources()` releases garbage pointers | Zero-init all members |
| 5 | Crash wrapping the back buffer | `_Get_DX8_Back_Buffer` leaves `bb` uninitialized **and** DXVK can return `D3D_OK` with a null back buffer | `bb = nullptr` + null-check; degrade the heat-haze effect instead of crashing |

Android-specific walls (the port's own story):

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 6 | Black screen forever; `VK_ERROR_NATIVE_WINDOW_IN_USE_KHR` on every present | An `ANativeWindow` accepts **one** producer. The engine's display-retry loop builds a doomed first device (blind `D3DFMT_D32` depth default → rejected) whose swapchain already connected the window; the failure path leaks the connection | `d3d9.deferSurfaceCreation = True` — surface created at first present, so only the surviving device touches the window |
| 7 | DXVK failures with empty error messages | DXVK statically linked libc++ → its exceptions carry private RTTI → swallowed by `catch(...)` across the `.so` boundary | Shared `libc++_shared.so` everywhere |
| 8 | Total silence, audio "initialized fine" | `__ANDROID__` **also defines `__linux__`** — a desktop-Linux workaround forced `ALSOFT_DRIVERS=pulse,alsa,…` (none exist on Android) → OpenAL null backend | Exclude Android from the Linux guard; OpenSL ES picked automatically |
| 9 | DXVK enumerates no adapters | Stock Adreno 650 driver is Vulkan **1.1**; DXVK 2.6 needs 1.3 | Bundle Mesa Turnip, load rootlessly via libadrenotools |
| 10 | Surface creation corrupts when SDL is involved | SDL loads its **own** copy of the Vulkan loader; DXVK's `VkInstance` means nothing to it | Patched WSI: take only the `ANativeWindow*` from SDL, create the surface via DXVK's loader |
| 11 | 3D world renders solid black with a "cleaner" one-device boot | Unknown — the 16-bit-**color** back buffer of the retry path is the only config that draws on this Turnip/Adreno path | Not fixed — the two-device boot is **load-bearing**; mystery [tracked → #8](https://github.com/fadi-labib/Generals-Android/issues/8) |

Touch & UI ([offered upstream → #11](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad/issues/11)):

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 12 | First tap after boot silently eaten | Desktop-ism: menu hides until the mouse *moves* 20 px; the tap's hover triggers the reveal transition and its deferred click lands on transition-**hidden** buttons (hit-testing skips hidden windows) | Auto-reveal the menu on touch platforms (the engine's own commented-out code, revived) |
| 13 | Panning zooms; zooming drifts the camera | Pan (held RMB at centroid) and pinch (wheel on distance) ran **simultaneously** from the same two fingers — physically inseparable signals | `TWO_PENDING` mode-lock: whichever signal crosses the threshold first owns the gesture |
| 14 | Taps randomly become drag-boxes | 8 px drag threshold ≈ **0.7 mm** on a 274 ppi panel — fingertip jitter crosses it | Physical thresholds: 3 mm via display DPI, floor 8 px |

Noise & hygiene:

| # | Symptom | Root cause | Fix |
|---|---------|-----------|-----|
| 15 | ~72,000 DXVK warnings per 12-minute session | Game sets `D3DRS_PATCHSEGMENTS` (ATI TruForm, 2002) per shader-apply; DXVK warns per call | N-patches are Windows-only now ([upstream → #12](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad/issues/12)) |
| 16 | 40 s of `[INI]`/`[SUBSYS]` boot spam per launch | Upstream debug tracing, useful once | Logcat pump filters it by default; `GENERALSX_VERBOSE` restores the firehose |
| 17 | macOS-recorded replays diverge on Android | Bionic vs Apple **libm**: transcendental drift accumulating over hundreds of sim frames | Not a bug — record replays on the platform that plays them; the harness self-records AI-vs-AI on-device |

## The lessons

Transferable to any old-engine port — each earned by an entry above:

1. **Allocator luck hides twenty-year-old bugs.** A new platform's `malloc` is a free
   fuzzer for uninitialized-memory assumptions. Expect the crash cascade; fix the
   class (zeroed allocation), not just the instances. *(#1–5)*
2. **`__ANDROID__` implies `__linux__`.** Every `#if defined(__linux__)` in the
   codebase is an unreviewed Android decision. Audit them all. *(#8)*
3. **One producer per `ANativeWindow`.** Any device/swapchain retry logic that can
   leak a connection will render black forever. `deferSurfaceCreation` exists for
   exactly this. *(#6)*
4. **Instrument, don't theorize.** The black screen fell to *counting log blocks*;
   the eaten tap fell to *tracing all six pipeline stages*. Both were unguessable
   from code reading alone — and both traces took under an hour. *(#6, #12)*
5. **Find the no-rebuild debugging channels.** DXVK reads `dxvk.conf` from the cwd —
   on Android that's `/sdcard`, so GPU options are A/B-testable with `adb push`.
   The black-screen fix was *proven* this way in minutes. *(#6)*
6. **Verify before believing.** The "obvious" one-device cleanup rendered black; the
   screenshot-size check (20 KB = black frame, multi-MB = content) caught it
   immediately. Every change gets the on-device regression checklist. *(#11)*
7. **Exceptions don't cross static-libc++ `.so` boundaries.** If a subsystem's
   errors read as `catch(...)`, check the STL linkage before anything else. *(#7)*
8. **Synthetic input lies.** `adb input tap` has a 0 ms down-up — the GUI never sees
   hover before click. `input swipe x y x y 150` emulates a real finger. *(#12)*
9. **Release asserts are no-ops here.** `WWASSERT` compiles away — engine invariants
   you read in the code do not hold at runtime. *(#2, #6)*
10. **Determinism is per-libm.** Cross-platform replay verification needs
    same-platform recordings. *(#17)*
11. **Write the handover as you go.** This port was fast because the previous one
    was documented. The [journey](ANDROID_JOURNEY.md), this ledger, and the
    [build guide's traps section](../BUILD/ANDROID.md#development-loop-debugging-and-traps)
    are the payment forward.
