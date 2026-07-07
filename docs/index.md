# Generals: Zero Hour — Native on Android

Command & Conquer Generals: Zero Hour running **natively on Android** — the real
engine (EA's GPL v3 source, via the GeneralsX lineage), not emulation.
Vulkan 1.3 (Mesa Turnip + DXVK), SDL3, OpenAL, touch controls.

![In-game on a Galaxy Tab S7+](BUILD/screenshots/android-tab-s7plus-ingame.png)

## The Android port (this project)

| Doc | What it covers |
|-----|----------------|
| [ANDROID.md](BUILD/ANDROID.md) | **The complete guide**: build from source, rendering pipeline, debugging toolbox, traps, known issues, regression checklist |
| [Renderer research](https://github.com/fadi-labib/Generals-Android/blob/main/docs/WORKDIR/planning/ANDROID_RENDERER_RESEARCH_2026-07.md) | Phase 0: how the Turnip-via-adrenotools route was chosen |
| [Port findings](https://github.com/fadi-labib/Generals-Android/blob/main/docs/WORKDIR/planning/ANDROID_PORT_FINDINGS_2026-07-06.md) | Codebase audit that shaped the plan |
| [Design spec](https://github.com/fadi-labib/Generals-Android/blob/main/docs/superpowers/specs/2026-07-06-android-port-design.md) · [Phase 0–2 plan](https://github.com/fadi-labib/Generals-Android/blob/main/docs/superpowers/plans/2026-07-06-android-port-phase0-2.md) · [Phase 3 plan](https://github.com/fadi-labib/Generals-Android/blob/main/docs/superpowers/plans/2026-07-06-android-port-phase3-renderer.md) | How the port was actually planned and executed (human + AI) |

## Inherited from the GeneralsX lineage

| Doc | What it covers |
|-----|----------------|
| [PORTING_PLAYBOOK.md](port/PORTING_PLAYBOOK.md) | Complete engineering log of the iOS port this one descends from |
| [PORTING_PATTERNS.md](port/PORTING_PATTERNS.md) | Generalized methodology for porting classic Windows games |
| [TOUCH_CONTROLS.md](port/TOUCH_CONTROLS.md) | The touch control system (iOS + Android): gestures, state machine, design rationale |
| [Getting the game files](HOWTO/GETTING_THE_GAME_FILES.md) | Obtaining your own copy of the game assets |
| [Known issues](KNOWN_ISSUES/README.md) · [Command-line parameters](ETC/COMMAND_LINE_PARAMETERS.md) | Engine-wide references |

macOS / iOS / iPad builds live in the parent project:
[ammaarreshi/Generals-Mac-iOS-iPad](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad).

## Contribute

- [Open issues](https://github.com/fadi-labib/Generals-Android/issues) — `good first issue` and `ai-ready` labels mark self-contained work
- [Discussions](https://github.com/fadi-labib/Generals-Android/discussions) — questions, testing reports, show & tell
- AI agents: read [AGENTS.md](https://github.com/fadi-labib/Generals-Android/blob/main/AGENTS.md) first

**You need your own Zero Hour game assets** — nothing here ships game data.
