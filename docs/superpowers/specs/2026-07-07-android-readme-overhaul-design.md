# Android README overhaul & docs consolidation — design

Date: 2026-07-07. Approved approach: **A — "the story is the hero"**.

## Goals

Make fadi-labib/Generals-Android read as a distinct, Android-first project that
credits its lineage generously, tells the porting story (inherited vs built vs
improved vs next), and is attractive and easy for contributors — human and AI.

## Decisions (user-ratified)

1. **AI framing**: prominent. The port is a human + AI collaboration and the README
   says so in the hero — "AI can't do this without human know-how."
2. **Old README**: replaced, not preserved locally. macOS/iOS readers are linked to
   the upstream repo (ammaarreshi/Generals-Mac-iOS-iPad).
3. **Pages scope**: publish everything Android-relevant; exclude only
   `BUILD/LINUX.md`, `BUILD/MACOS.md`, `DEV_BLOG/` (upstream desktop story).
   Add `jekyll-sitemap` + `jekyll-seo-tag`.
4. **ANDROID_HANDOVER.md is deleted**; its unique content merges into
   `docs/BUILD/ANDROID.md` (debugging toolbox, traps, iteration loop, key files,
   patch-regeneration rule, prioritized next steps, regression checklist).
   Machine-specific lines (adb serial, personal token setup) are dropped, not moved.
5. **Prev work stays intact**: docs/port/, HOWTO/, KNOWN_ISSUES/, ETC/ unchanged.

## README structure (replacement)

Hero (title, badges, screenshot, pitch + pipeline chain) → human+AI passage →
Get it (Releases APK, device requirements, BYO assets) → What works / what doesn't
(status + honest known issues, linked to issues) → The porting story (Inherited /
Built here / Improved / Next) → Build from source (short block → ANDROID.md) →
Port your own game (PORTING_PLAYBOOK/PATTERNS) → Contributing (AI-first) →
Lineage & credits (upstream chain + ammaarreshi as direct parent) → License.

## Reference updates

Issues #1–#6 bodies, discussion #7, CONTRIBUTING.md, docs/index.md: handover links
→ ANDROID.md anchors. Shared Claude Code onboarding guide re-uploaded from the
merged ANDROID.md.
