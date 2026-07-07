---
description: Can you play C&C Generals Zero Hour on Android? Which devices work, do you need root, where do the game files come from — direct answers.
---

# FAQ

## Can you play Command & Conquer Generals: Zero Hour on Android?

**Yes — natively.** This project compiles the real 2003 engine (EA's GPL v3 source
release) for arm64 Android. It renders DirectX 8 through DXVK to Vulkan 1.3 and plays
skirmish matches at 30–60 FPS on a Galaxy Tab S7+. It is not an emulator, not a
streaming client, and not a remake.

## Which Android devices are supported?

Devices with a **Qualcomm Adreno 6xx or 7xx GPU** (e.g. Snapdragon 855/865/888/8-Gen
phones and tablets). The port bundles the Mesa Turnip Vulkan driver, which only
supports Adreno. Samsung Exynos (Xclipse) and Mali GPUs don't work yet — that's
[tracked here](https://github.com/fadi-labib/Generals-Android/issues/9).

## Do I need root?

**No.** The bundled Turnip driver is loaded rootlessly via
[libadrenotools](https://github.com/bylaws/libadrenotools), which redirects the
Vulkan driver inside the app's own process. Nothing on the system is modified.

## Where do I get the APK?

From the project's
[Releases page](https://github.com/fadi-labib/Generals-Android/releases). The APK is
debug-signed for sideloading; Samsung devices may need Play Protect's adb
verification and Auto Blocker disabled
([how-to](BUILD/ANDROID.md#samsung-sideload-gotcha)).

## Where do the game files come from?

**From your own copy of the game.** The APK contains no game assets — Zero Hour's
data files are copyrighted and are not distributed here. Buy the game
([Steam](https://store.steampowered.com/app/2732960/), often ~$5) and push your
files to the device with the provided script
([details](BUILD/ANDROID.md#assets)).

## Is this legal?

The **engine code** is EA's official GPL v3 source release, forked through a chain of
community ports — everything here complies with that license. The **game assets**
(art, audio, maps) remain EA's copyrighted content, which is why you must supply your
own purchased copy.

## How does a DirectX 8 game run on Android?

Through a translation chain, all in-process:
DirectX 8 → [DXVK](https://github.com/doitsujin/dxvk) (D3D8/9 → Vulkan) →
**Vulkan 1.3** on [Mesa Turnip](https://docs.mesa3d.org/drivers/freedreno.html)
(bundled, because stock Adreno drivers only expose Vulkan 1.1) → the Android surface.
Full technical detail: [rendering pipeline](BUILD/ANDROID.md#rendering-pipeline-phase-3).

## How do the touch controls work?

A gesture translator converts touch into the mouse events the 2003 engine expects:
tap = select, drag = selection box, long-press = right-click (deselect), two-finger
drag = camera pan, pinch = zoom. Design and rationale:
[Touch controls](port/TOUCH_CONTROLS.md).

## Does multiplayer work?

Untested. The GameSpy-era networking code compiles but online play hasn't been
attempted on Android. Skirmish vs AI is the tested mode; campaign and Generals
Challenge are [being verified](https://github.com/fadi-labib/Generals-Android/issues/12).

## How was this ported in under 24 hours?

By standing on documented shoulders: the iOS/iPadOS parent port had already solved
the DirectX-on-mobile renderer chain, the touch translation, and the app lifecycle —
and written it all down. Android's own walls (a Vulkan 1.1 driver, a one-producer
window rule, a dirty allocator unmasking 2003-era bugs) are told in
[The Android Journey](journey/ANDROID_JOURNEY.md), and every defect found is cataloged
in [Bugs & Lessons](journey/BUGS_AND_LESSONS.md).

## Can I play this on iPhone, iPad, or Mac?

Yes — via the parent project this port descends from:
[ammaarreshi/Generals-Mac-iOS-iPad](https://github.com/ammaarreshi/Generals-Mac-iOS-iPad).

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Can you play Command & Conquer Generals: Zero Hour on Android?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes, natively. The project compiles the real 2003 engine (EA's GPL v3 source release) for arm64 Android, rendering DirectX 8 through DXVK to Vulkan 1.3. It plays skirmish matches at 30-60 FPS. It is not an emulator, streaming client, or remake."
      }
    },
    {
      "@type": "Question",
      "name": "Which Android devices are supported?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Devices with a Qualcomm Adreno 6xx or 7xx GPU (Snapdragon 855 and newer). The bundled Mesa Turnip Vulkan driver only supports Adreno; Exynos/Xclipse and Mali GPUs are not supported yet."
      }
    },
    {
      "@type": "Question",
      "name": "Do I need root to play Generals Zero Hour on Android?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. The bundled Turnip Vulkan driver is loaded rootlessly via libadrenotools inside the app's own process; the system is not modified."
      }
    },
    {
      "@type": "Question",
      "name": "Are the game files included?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. The APK ships no game assets. You need your own purchased copy of Zero Hour (sold on Steam) and push its files to the device with the provided script."
      }
    },
    {
      "@type": "Question",
      "name": "Is this legal?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The engine code is EA's official GPL v3 source release and the port complies with that license. Game assets remain EA's copyrighted content, which is why players supply their own purchased copy."
      }
    }
  ]
}
</script>
