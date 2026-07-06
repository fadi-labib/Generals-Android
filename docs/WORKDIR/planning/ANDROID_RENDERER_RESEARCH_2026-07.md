# Android Renderer Research (Phase 0)

Decides the Phase-3 renderer route for the Android port.
Spec: docs/superpowers/specs/2026-07-06-android-port-design.md

> **Status legend used throughout:** **[MERGED]** = in an upstream release/master and
> demonstrably working; **[WIP]** = exists on a branch/PR/community fork, not upstream-stable;
> **[CLAIM]** = asserted in a README/forum/marketing without an artifact I could verify;
> **[NEG]** = a negative result (searched, found no evidence).
>
> Scope note: our use case is a **native arm64 ELF game that links dxvk-native directly**
> (SDL3 window → DXVK d3d8/d3d9 → Vulkan). This is **not** the Winlator/Mobox use case, which
> runs **x86 Windows** games under Box64 + Wine and loads DXVK as a **Windows PE DLL**. Keep the
> two lanes separate — evidence from one does not transfer to the other.

---

## 1. DXVK on Android — prior art

### 1.1 Upstream DXVK: does it target Android?

| Question | Finding | Status | Evidence |
|---|---|---|---|
| Is dxvk-native a separate project? | No longer. `dxvk-native` (originally Joshua-Ashton/misyltoad) was **upstreamed into DXVK 2.0** (Oct 2022). Native builds are now first-class in the main repo. | **[MERGED]** | [Phoronix: DXVK 2.0 Released](https://www.phoronix.com/news/DXVK-2.0-Released); origin repo [Joshua-Ashton/dxvk-native](https://github.com/Joshua-Ashton/dxvk-native) |
| Does `meson.build` have any Android branch? | **No.** The build splits exactly two ways: `if platform == 'windows'` (Win32 WSI) vs `else` (non-Windows native). The `else` branch **requires SDL3, SDL2, or GLFW** ("SDL3, SDL2, or GLFW are required to build dxvk-native"). No `host_machine.system() == 'android'` conditional, no bionic handling. | **[MERGED]** (verified in source) | [dxvk/meson.build @ master](https://github.com/doitsujin/dxvk/blob/master/meson.build) |
| WSI backends available for native | `DXVK_WSI_SDL3`, `DXVK_WSI_SDL2`, `DXVK_WSI_GLFW` — selected at runtime via `DXVK_WSI_DRIVER`. **SDL3 is a supported backend** (matches our existing SDL3 stack). | **[MERGED]** | meson.build (above); [issue #3321](https://github.com/doitsujin/dxvk/issues/3321) |
| Vulkan version floor | **DXVK 2.0+ makes Vulkan 1.3 mandatory.** Any device/driver capping at Vulkan 1.1/1.2 cannot run mainline DXVK ≥2.0. | **[MERGED]** | [DXVK-Sarek README](https://github.com/pythonlover02/DXVK-Sarek) (documents the 1.3 requirement it forks around) |
| Official stance on Android | DXVK **explicitly does not officially support Android or proprietary mobile drivers.** A memory-allocation fix note states improvements "do not mean DXVK will officially support Android." Tracking issue [#1183 "DXVK with android"](https://github.com/doitsujin/dxvk/issues/1183) (opened Sep 2019) was **closed with no working solution / no maintainer commitment.** | **[MERGED]** (stance), **[NEG]** (no support) | [issue #1183](https://github.com/doitsujin/dxvk/issues/1183); [DXVK wiki: Driver support](https://github.com/doitsujin/dxvk/wiki/Driver-support) |

**Takeaway for section 5 (do not decide here):** Upstream dxvk-native has *no Android build target*, but nothing in the build is structurally Windows-only for the native path — the blockers are (a) building the tree against bionic/NDK, (b) an SDL3 WSI that talks to `ANativeWindow`, and (c) the mandatory Vulkan 1.3 floor. None of these is validated by upstream; all three are our porting risk.

### 1.2 Native arm64 dxvk-native on Android — direct precedents

| Precedent | What it is | Status | Evidence |
|---|---|---|---|
| Any shipped native arm64 Android app linking dxvk-native (no Wine) | **None found.** Extensive GitHub/web search surfaced no native-ELF Android game or app that links dxvk-native directly. The closest same-family project is **this repo's own lineage** (GeneralsX: SDL3+DXVK+MoltenVK) which targets macOS/iOS, **not** Android. | **[NEG]** | search returned only Wine-based distros (§1.3) + GeneralsX (macOS/iOS) |
| `dxvk-arm64ec` (StevenMXZ) | Fork adding **ARM64EC** (Windows-on-Arm ABI) builds — for Wine/emulation on Arm Windows, **not** Android/bionic native. Not relevant to our lane. | **[WIP]** | [StevenMXZ/dxvk-arm64ec](https://github.com/StevenMXZ/dxvk-arm64ec) |

> **Load-bearing negative result:** there is **no proven native-arm64-Android dxvk-native precedent**. Our port would be, as far as this survey found, a first. Task 4 must weight this as genuine bring-up risk, not a solved path.

### 1.3 Wine/Box64 distros (adjacent lane — DXVK ships as x86 PE, NOT native arm64)

These are the projects most people mean by "DXVK on Android." **All run x86/x86_64 Windows games via Box64 (x86→arm64 dynarec) + Wine, and load DXVK as the stock Windows `d3d8/d3d9/d3d11.dll` PE build inside Wine.** They are evidence that *DXVK-generated Vulkan works on Android GPUs*, but **not** that dxvk-native builds/links as a native arm64 ELF.

| Distro | Repo | DXVK form | Notes | Status |
|---|---|---|---|---|
| Winlator (winebox64) | [winebox64/winlator](https://github.com/winebox64/winlator) | Windows PE DLL under Wine+Box64/FEXCore | Modular `.wcp` components let users swap DXVK/Wine/driver. DXVK 2.7 needs Box64 ≥0.3.7. | **[MERGED]** (as x86-lane) |
| Winlator101 (K11MCH1) | [K11MCH1/Winlator101](https://github.com/K11MCH1/Winlator101/releases) | same | Active community fork w/ releases. | **[MERGED]** |
| Mobox (olegos2) | [olegos2/mobox](https://github.com/olegos2/mobox) | Windows PE DLL under Wine (Termux) | README offers "Turnip+DXVK" for "Adreno 6xx or 725–740". Confirms DXVK+Turnip pairing on-device. | **[MERGED]** |
| Termux-box (olegos2) | [olegos2/termux-box](https://github.com/olegos2/termux-box) | same | "preconfigured rootfs with Box86, Box64, Wine and DXVK". | **[MERGED]** |
| Box64Droid (Ilya114) | [Ilya114/Box64Droid](https://github.com/Ilya114/Box64Droid) | same | **EOL June 2025.** | **[MERGED, EOL]** |
| BoxWine (ShephardOS9) | [ShephardOS9/BoxWine](https://github.com/ShephardOS9/BoxWine) | same | DXVK + Box86/64 + Turnip interface. | **[CLAIM]** (not deeply verified) |

**Distinction to carry into the decision:** these prove DXVK's *Vulkan output* runs on Adreno/Turnip on 2020+ phones (strong signal for our renderer). They prove **nothing** about compiling dxvk-native against the NDK/bionic or an SDL3-Android WSI — the two hard parts of our lane are untested by any of them.

### 1.4 Fallback fork if the Vulkan 1.3 floor bites

| Fork | Purpose | Relevance | Status | Evidence |
|---|---|---|---|---|
| **DXVK-Sarek** (pythonlover02) | DXVK fork for **GPUs/drivers limited to Vulkan 1.1/1.2** (mainline DXVK 2.0 forces 1.3). Explicitly **made `transformFeedback` optional so low-end Adreno 6xx can run D3D10/11 on the proprietary Qualcomm driver**; adds Adreno 5xx compat. | Direct fallback if we must target a **stock** Adreno/Mali driver that lacks Vk 1.3 or `transformFeedback`. Our game is D3D8/D3D9 (lighter than D3D11), improving odds. | **[WIP]** (active fork, not upstream) | [pythonlover02/DXVK-Sarek](https://github.com/pythonlover02/DXVK-Sarek); [GamingOnLinux: Sarek v1.12](https://www.gamingonlinux.com/2026/04/gaming-on-linux-with-an-older-gpu-levels-up-with-dxvk-sarek-v1-12-bringing-major-new-features/) |

---

## 2. Driver landscape (stock Adreno/Mali vs Turnip)

### 2.1 Turnip (Mesa freedreno Vulkan) — device coverage & kernel backends

| Aspect | Finding | Status | Evidence |
|---|---|---|---|
| What it is | Turnip = Mesa's open-source **Vulkan 1.3** driver for Qualcomm Adreno (part of freedreno). | **[MERGED]** | [Mesa docs: freedreno](https://docs.mesa3d.org/drivers/freedreno.html) |
| GPU coverage | **Adreno 6xx: fully supported, Vulkan 1.3.** Docs state "no plans to port to a5xx or earlier." **Adreno 7xx: partial** — a730/a740 merged; **a750 still in review** as of the survey; tiled rendering / 7xx-specific optimizations still missing. | 6xx **[MERGED]**, 7xx **[WIP]** | [Mesa docs: freedreno](https://docs.mesa3d.org/drivers/freedreno.html); [Phoronix: Turnip A700 initial support](https://www.phoronix.com/news/TURNIP-Vulkan-Adreno-A700) |
| Kernel backend (the Android-critical part) | Turnip can target **three** kernel submission backends: **MSM DRM** (mainline Linux), **KGSL** (Qualcomm's out-of-tree Android kernel driver), and **Virtio**. The **KGSL backend was merged into Mesa 20.3-devel**, which is what lets Turnip run on a **stock, unmodified Android kernel** (no custom ROM). Android gralloc handled in `tu_android.c`. | **[MERGED]** | [Phoronix: Turnip up and running on KGSL](https://www.phoronix.com/news/TURNIP-KGSL-Vulkan-Bringup); [DeepWiki: Turnip backends](https://deepwiki.com/bminor/mesa-mesa/2.3-turnip-qualcomm-vulkan-driver) |
| Not for Mali/Xclipse | Turnip is **Adreno-only.** Mali and Samsung Xclipse devices have **no Turnip path** — they are stuck with their stock drivers. | **[MERGED]** | freedreno docs (above) |

### 2.2 App-bundled driver loading (adrenotools) — the delivery mechanism

> BCn/texture-format implications are **Task 3** — deliberately out of scope here. This subsection covers only the *driver-loading mechanics*.

| Aspect | Finding | Status | Evidence |
|---|---|---|---|
| Library | **libadrenotools** (bylaws) — rootless replacement/override of the Adreno GPU driver, **per-app**. | **[MERGED]** | [bylaws/libadrenotools](https://github.com/bylaws/libadrenotools) |
| Requirements | **Android 9+, arm64.** No root. | **[MERGED]** | libadrenotools README |
| Mechanism | Android apps don't `dlopen` the GPU driver directly — the loader `libvulkan.so` opens the vendor `libvulkan.adreno.so`. adrenotools **hooks that load via the linker namespace** and substitutes a user-provided driver `.so`. **Each app must explicitly integrate the library** and point it at a driver file; it is not system-wide. | **[MERGED]** | [libadrenotools/src/driver.cpp](https://github.com/bylaws/libadrenotools/blob/master/src/driver.cpp); [XDA writeup](https://www.xda-developers.com/adreno-tools-update-android-graphics-drivers/) |
| Driver package format | Turnip is shipped as an **adrenotools `.zip`**: `meta.json` + `libvulkan_freedreno.so`. Automated CI builds exist. | **[MERGED]** | [Weab-chan/freedreno_turnip-CI](https://github.com/Weab-chan/freedreno_turnip-CI); [K11MCH1/AdrenoToolsDrivers](https://github.com/K11MCH1/AdrenoToolsDrivers/releases/) |
| Proven consumers | Skyline/Strato, Yuzu/Eden, AetherSX2, Vita3K all ship it; **PPSSPP merged custom driver loading** ([PR #18532](https://github.com/hrydgard/ppsspp/pull/18532)); RetroArch has open requests ([#18143](https://github.com/libretro/RetroArch/issues/18143)). Pattern is mature and battle-tested in Android emulators. | **[MERGED]** | links in cell |
| License / GPL bundling | Mesa/Turnip is **MIT-licensed (permissive)** → no GPL conflict when bundling or shipping alongside a GPL/mixed-license app; adrenotools loads it as a **separate runtime `.so`** anyway, further insulating licensing. (Confirm final license posture in Task 4.) | **[CLAIM]** (Mesa MIT is well-known; not re-verified against a LICENSE file here) | — |

**Implication (for §5):** Turnip on Adreno is deliverable to unmodified retail phones **without root** via a well-worn path — but it's **Adreno-only, Android-9+, and requires we integrate adrenotools + ship/bundle a driver zip.** Mali/Xclipse users get no Turnip and fall back to §2.3.

### 2.3 Stock vendor Vulkan drivers on 2020+ flagships

| Vendor / GPU | Vulkan level | Notes | Status | Evidence |
|---|---|---|---|---|
| Qualcomm Adreno 6xx/7xx | **Vulkan 1.3** conformant | Adreno 660/730/740 etc. listed as Vulkan-conformant. **Updatable GPU drivers via Play Store since Adreno 640 / Snapdragon 855** — stock driver can be newer than shipped ROM. | **[MERGED]** | [Khronos Vulkan conformant products](https://www.khronos.org/conformance/adopters/conformant-products/vulkan); [Wikipedia: Adreno](https://en.wikipedia.org/wiki/Adreno) |
| ARM Mali | Vulkan 1.3 requires **Mali-G77 or newer** (Valhall+). Older Mali (Bifrost G5x/G7x) cap lower. | Mainline DXVK 2.0 (Vk 1.3) needs G77+; older Mali → DXVK-Sarek territory (§1.4). No Turnip fallback. | **[MERGED]** | [Khronos conformant products](https://www.khronos.org/conformance/adopters/conformant-products); [Mali GPU overview](https://electronics.alibaba.com/question/mali-gpu-explained-performance,-use-cases-how-to-compare) |
| Samsung Xclipse (RDNA2, Exynos 2200+) | Vulkan-conformant, but **thin field data**; historically buggy drivers. | Treat as high-risk/unknown; no Turnip path. | **[CLAIM]** (limited evidence found) | — |
| Stock driver quality (general) | Adreno stock drivers are generally the most robust for gaming; Turnip often **ships fixes/features ahead of Qualcomm's proprietary driver**, which is the main reason emulators bundle it. | **[CLAIM]** (community consensus, forum-sourced) | [XDA / community](https://www.xda-developers.com/adreno-tools-update-android-graphics-drivers/) |

**Net driver picture for §5:** On modern **Adreno** flagships we have **two** viable Vulkan paths — the **stock Qualcomm driver (Vk 1.3, decent)** and **bundled Turnip via adrenotools (often better, Adreno-only, Android 9+)**. On **Mali G77+ / Xclipse**, only the **stock driver** exists, and driver quality/`transformFeedback` gaps may force **DXVK-Sarek** or degrade compatibility. The BCn/texture-format angle (which drivers expose desktop DXT formats, and whether adrenotools' BCn-enable helps) is deferred to **Task 3**.

---

## 3. BCn/DXT texture format support matrix

> Same status legend as §1 ([MERGED]/[WIP]/[CLAIM]/[NEG]).
>
> **Why this section exists:** the retail assets are DDS textures compressed as **BC1/BC2/BC3
> (= DXT1/DXT3/DXT5)**. Our lane is dxvk-native translating D3D8 → the D3D8 texture layer needs
> the matching `VK_FORMAT_BC{1,2,3}_*_BLOCK` with the **`SAMPLED_IMAGE`** feature bit on the
> device — which the Vulkan spec ties to the single **`textureCompressionBC`** physical-device
> feature (enable it and BC1–BC7 must all report `SAMPLED_IMAGE` + `BLIT_SRC` +
> `SAMPLED_IMAGE_FILTER_LINEAR`). So the whole question collapses to: *does this GPU/driver set
> `textureCompressionBC = true`?* If not, DXVK has no native path for those formats and we need a
> mitigation (below). ([Vulkan spec: features](https://docs.vulkan.org/spec/latest/chapters/features.html);
> [Vulkan spec: formats/mandatory](https://docs.vulkan.org/spec/latest/chapters/formats.html))

**Key upstream fact that reframes everything:** BCn is a *desktop* format, but **Adreno hardware
has silently supported BCn/S3TC for years** — Qualcomm just didn't *expose* it in the proprietary
driver until the **Snapdragon 865 / Adreno 650 era** (speculated to track BCn patent expiry). This
is exactly why Android emulators bundle either Turnip or a driver patch to unlock it.
([Esper: Android Dessert Bites 14 — GPU driver updates](https://www.esper.io/blog/android-dessert-bites-14-gpu-driver-updates-3819534))

### 3.1 Support matrix (BC1/BC2/BC3 = DXT1/DXT3/DXT5, sampled)

| GPU / driver | BC1 | BC2 | BC3 | Status | Source |
|---|---|---|---|---|---|
| **Adreno 7xx (stock Qualcomm)** | ✅ | ✅ | ✅ | **[CLAIM]** (post-865 era → BC exposed; gpuinfo-verifiable per-SKU) | HW supports BCn, Qualcomm exposes it since SD865/Adreno 650, all 7xx are newer ([Esper](https://www.esper.io/blog/android-dessert-bites-14-gpu-driver-updates-3819534)); coverage query: [gpuinfo BC1_RGBA / Android](https://vulkan.gpuinfo.org/listdevicescoverage.php?platform=android&format=VK_FORMAT_BC1_RGBA_UNORM_BLOCK) |
| **Adreno 6xx (stock Qualcomm)** | ⚠️ | ⚠️ | ⚠️ | **[CLAIM]** — **split**: Adreno **650+ (SD865+): yes**; older **6xx (630/640, SD855-era): no** | BCn exposure gated at SD865/Adreno 650 ([Esper](https://www.esper.io/blog/android-dessert-bites-14-gpu-driver-updates-3819534)); stock vs Turnip reports enumerated in [cpu-gpu-arch/Adreno-600 refs](https://raw.githubusercontent.com/azhirnov/cpu-gpu-arch/main/gpu/Adreno-600.md) → [gpuinfo Adreno 660](https://vulkan.gpuinfo.org/listreports.php?devicename=Adreno%20(TM)%20660) |
| **Adreno 6xx/7xx (Turnip / Mesa)** | ✅ | ✅ | ✅ | **[MERGED]** — verified in Mesa `main` source | Turnip sets `features->textureCompressionBC = !pdevice->info->props.is_a702;` — **true on all Turnip-supported Adreno *except* the entry-level a702**. The a702 hardware lacks BC6H/BC7 (`/* no BC6H & BC7 support on A702 */`), and because Vulkan's `textureCompressionBC` is **all-or-nothing** (enabling it mandates all of BC1–BC7), Turnip disables the whole feature bit there — **a702 is a NO for BC1/2/3 too**. Flagship 6xx/7xx targets are unaffected. ([tu_device.cc L444-447, mesa/main](https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/freedreno/vulkan/tu_device.cc)) |
| **Mali G7x / Immortalis (stock ARM)** | ❌ | ❌ | ❌ | **[MERGED]** (negative) — **no BCn hardware, no Turnip fallback** | ARM GPUs support only **ETC/ETC2/ASTC + AFBC/AFRC**; ARM docs never list BC/DXT. ([Arm GPU Best Practices — textures](https://developer.arm.com/mobile-graphics-and-gaming/vulkan-api-best-practices-on-arm-gpus); [ARM Mali ASTC](https://arm-software.github.io/vulkan-sdk/_a_s_t_c.html)) Turnip is Adreno-only (§2.1). |
| **Samsung Xclipse 920/940 (RDNA2/3, stock)** | ⚠️ | ⚠️ | ⚠️ | **[CLAIM]** — RDNA HW has native BCn; **BC1–BC3 native where the Samsung driver exposes it**, field data thin/buggy | RDNA is a desktop arch with native BCn; the ExynosTools layer notes "**BC1–BC3 can remain native where supported by the driver**" and only virtualizes BC4/5/6H/7. Treat as high-risk/verify-on-device. ([WearyConcern1165/ExynosTools](https://github.com/WearyConcern1165/ExynosTools); §2.3 Xclipse row) |
| **Actual device (ground truth)** | — | — | — | **pending (no device connected)** | `adb devices` empty this session — see §3.4 for the exact capture commands |

Legend: ✅ native `textureCompressionBC`/`SAMPLED_IMAGE` support · ⚠️ conditional/driver-dependent (verify per-SKU on gpuinfo or on-device) · ❌ not supported natively (needs a §3.2 mitigation).

**Bottom line of the matrix:** exactly **one route gives BC1/2/3 across the board: Adreno + Turnip**
— on all Turnip-supported Adreno **except the entry-level a702**, where the all-or-nothing
`textureCompressionBC` bit is disabled entirely (flagship 6xx/7xx targets are fine); this is the same
adrenotools-bundled path §2.2 already establishes. Stock Adreno is fine on **SD865/Adreno
650 and newer** and needs a mitigation on older 6xx. **Mali is a hard "no"** (no HW, no Turnip) and
is the only route that *requires* an asset- or app-side mitigation. **Xclipse is a "probably-yes,
verify"** for BC1–3.

### 3.2 Mitigations for the "no" / "conditional" cells

| Cell needing help | Mitigation | Cost / caveat | Status | Source |
|---|---|---|---|---|
| Older stock Adreno 6xx (BC hidden) | **Ship Turnip** (native BC, §3.1 row 3) — or **BCeNabler / adrenotools** force-exposes BCn on the *stock* Qualcomm driver, rootless | Turnip = the path we already plan (§2.2); BCeNabler is Adreno-only and Android 9+ | **[MERGED]** | [bylaws/libadrenotools](https://github.com/bylaws/libadrenotools) ("enabling BCn textures"); [Esper](https://www.esper.io/blog/android-dessert-bites-14-gpu-driver-updates-3819534) |
| Samsung Xclipse (BC4–7 gaps; BC1–3 driver-dependent) | **ExynosTools** compat layer — reports/virtualizes missing BC formats via CPU/compute, keeps BC1–3 native where possible | Non-mainline community layer; BC1–3 (what we need) usually native, so may be unnecessary | **[WIP]** | [WearyConcern1165/ExynosTools](https://github.com/WearyConcern1165/ExynosTools) |
| **Mali (no BCn at all)** | Only real options: **(a) offline transcode** the DDS assets DXT→**ASTC/ETC2** + a texture-interception shim so DXVK's D3D8 path is fed a Mali-native format, **or (b) a runtime CPU/compute BCn→RGBA8 decode** in the upload path. **DXVK has no built-in software BCn decode** — it advertises the native `VkFormat` and the format is simply absent if `textureCompressionBC` is false. | (a) needs a build pipeline + a format-remap layer and re-QA of every texture; (b) burns CPU/compute at load and inflates memory (see §3.3). **No off-the-shelf drop-in exists for our native-ELF lane.** | **[NEG]** (no ready-made path) | DXVK relies on native VkFormats (§1); no BCn-decode option surfaced in the DXVK tree |
| Any (last resort, all GPUs) | **Ship decompressed RGBA8** | See §3.3 — **infeasible on mobile** (4–8× size blow-up) | **[NEG]** | size math below |

### 3.3 Asset-side transcode cost (why "just decompress to RGBA8" is a non-starter)

- **Bit budget:** BC1 = **4 bpp**, BC2/BC3 = **8 bpp**, vs uncompressed **RGBA8 = 32 bpp**. Decompressing to RGBA8 is therefore a **8× blow-up from BC1** and **4× from BC2/BC3**.
- **Scale:** the game ships **thousands of DDS textures** across its `.big` archives, **~2.7 GB of total assets**. (These are user-supplied retail assets — **none are checked into this repo**: `find -iname '*.dds'` / `*.big` returns 0, as expected.) A wholesale RGBA8 expansion pushes the texture working set from GB-scale toward **tens of GB** of storage and blows past mobile RAM/VRAM budgets — a non-starter for install size and runtime memory alike.
- **The sane non-BC mitigation is a lateral transcode**, DXT → **ASTC or ETC2** (both are also ~4–8 bpp block formats, so **no size blow-up**) — but that is an **offline build-pipeline** change plus a **texture-remap shim** feeding DXVK's D3D8 path a Mali-native format, and it re-opens quality/QA on every texture. Sizing and go/no-go for the Mali route belong to **Task 4**.

### 3.4 Device ground-truth capture (run when a device is attached)

No device was connected during this research (`adb devices` returned an empty list). When one is attached, capture the ground-truth row with the brief's commands:

```bash
adb shell getprop ro.product.model ro.soc.model
adb shell cmd gpu vkjson > /tmp/vkjson.txt 2>/dev/null || true
grep -iE 'BC1|BC2|BC3|textureCompressionBC' /tmp/vkjson.txt
```

Record `textureCompressionBC` (feature) and the `VK_FORMAT_BC{1,2,3}_*_BLOCK` `optimalTilingFeatures` (look for `SAMPLED_IMAGE`) as the ground-truth row, noting whether the reading is from the **stock** driver or a **bundled Turnip** build.



## 4. SDL3 on Android + precedent ports

<!-- Owned by a later task. Intentionally left as a heading. -->

## 5. DECISION

<!-- Owned by Task 4. Intentionally left as a heading. -->
