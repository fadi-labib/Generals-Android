## What & why

<!-- One paragraph. Link the issue this closes: "Closes #N". -->

## AI assistance disclosure

<!-- Required by CONTRIBUTING.md. Delete the rows that don't apply. -->

| | |
|---|---|
| Agent/model used | <!-- e.g. Claude Code (Fable 5), Copilot, none --> |
| Extent | <!-- fully generated / generated then human-edited / human-written with AI review --> |
| Human verification done | <!-- what YOU checked, built, and ran — reviewers will not do this for you --> |

<!-- Agent authors: paste your verification evidence (build output, logcat lines,
     test results) rather than asserting success. Do not open PRs you could not verify. -->

## Verification

- [ ] Builds on the platform(s) this change touches (state which preset: `linux64-deploy` / `macos-vulkan` / `android-vulkan`)
- [ ] No unrelated lines changed (see CONTRIBUTING.md scope rules)

### Android on-device regression (required if the change can affect the Android runtime)

- [ ] Boots to the main menu with the animated shell map
- [ ] `Actual swapchain properties` in logcat; zero `NATIVE_WINDOW_IN_USE`, zero crashes
- [ ] Single tap opens SOLO PLAY submenu
- [ ] Skirmish loads: map select → PLAY GAME → in-game HUD with running clock
- [ ] Audio active (`dumpsys media.audio_flinger` shows tracks, not standby)
- [ ] HOME → relaunch: same PID, rendering resumed

<!-- No device? Say so — a maintainer or tester can run the checklist, but the PR
     stays unmerged until someone has. -->
