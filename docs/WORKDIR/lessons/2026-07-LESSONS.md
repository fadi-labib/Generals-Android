# Lessons — July 2026

## 2026-07-06: Full codebase read-through (Android port preparation)

Systematic read of the port-relevant codebase before planning the Android port.
Companion findings doc: `docs/WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md`.

### Lessons that generalize

1. **Platform isolation held up under audit.** A guard-density sweep
   (`grep -rl '_WIN32|__APPLE__|__linux__'`) found 1 guarded file in all of
   GameLogic and 2 in GameClient. The AGENTS.md rule ("no platform code in
   game logic") is enforced reality, not aspiration. Any new platform work
   must keep it that way — the sweep is cheap; run it after big changes.

2. **Trust artifacts, not exit codes.** Three separate silent failures in the
   port history (DXVK compiling the SDL2 WSI instead of SDL3, stale dylibs
   shipped twice) all returned green exits. Standard checks:
   `strings <lib> | grep WsiDriver`, `nm -u`, `otool -l` / `readelf -h` for the
   target platform, `lipo -info` for arch.

3. **The deferred-commit input pattern is the load-bearing touch design.** On
   finger-down send nothing; commit tap/drag/pan/long-press only when the
   gesture identifies itself. A "cancelled" synthetic LMB is still a real
   click to the 2003 GUI (rally points!). Also: long-press timers must be
   polled from the frame loop — a stationary finger emits zero events.

4. **Synthetic SDL events must carry a valid `windowID`.**
   `SDL3Mouse::scaleMouseCoordinates()` maps window pixels → internal render
   resolution via `SDL_GetWindowFromID` and silently skips scaling on lookup
   failure. Symptom: taps land increasingly off toward screen edges.

5. **"End of stream" needs two agreeing signals.** The chirp/silent-EVA bug
   class: what the decoder says (EOF) and what the buffer queue does (growth)
   must agree; disagreement is termination-with-bounded-retry, never
   wait-forever. Three consecutive no-growth probes latch EOF
   (`OpenALAudioStream::update()`), counter reset on any healthy refill.

6. **Fallback paths inherit hidden assumptions.** When MoltenVK failed the
   radar caps query wholesale, ALL radar textures rode a fallback that
   silently dropped alpha → black minimap. A fallback written for one weird
   case becomes the main path on a new platform; make fallbacks per-caller.

7. **Old-code locale traps on POSIX.** `vswprintf` returns -1 for non-ASCII
   wide format strings under the "C" locale (broke Cyrillic); `<xlocale.h>`
   is Apple-only. Fixed centrally in `UnicodeString::format_va` with a static
   UTF-8 `locale_t` + `uselocale` — fix at the layer you control.

8. **Exit semantics differ.** Windows `ExitProcess` skips global C++ dtors;
   POSIX `return main()` runs them → pool-allocator dtors crash on freed
   backing memory. `_exit()` after explicit cleanup is the deliberate,
   correct choice in `SDL3Main.cpp` — do not "clean it up".

9. **Read-only trees still carry junk**: `GameText.cpp.orig/.rej`,
   `W3DShaderManager.cpp.bak2` exist in-tree. Don't treat them as source; and
   they're candidates for a hygiene commit.

10. **The env-var registry is the universal config escape hatch.**
    `CNC_ZH_*` / `CNC_GENERALS_*` env vars are checked before registry.ini and
    all auto-detection. On any new platform (Android via JNI `setenv`), this
    is the cheapest way to wire paths/language before the engine starts.

### Bug found

`endian_compat.h` letoh 32/64-bit helpers call `le16toh` — see
`docs/WORKDIR/audit/BUG_ENDIAN_COMPAT_LETOH_2026-07-06.md`.
