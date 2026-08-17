# LineageOS 18.1 for the GPD XD+

Unofficial **Android 11** for the GPD XD+ (`xdplus`), a MediaTek MT8176 handheld from 2018 that shipped with Android 7.0 and was left there.

This repository is the umbrella: it holds the documentation, the build and install scripts, and the releases. It is **not** a build tree — the actual sources live in the [component repos](#the-repos).

---

- [What this is](#what-this-is)
- [Why this exists](#why-this-exists)
- [A note on how this was built](#a-note-on-how-this-was-built)
- [The repos](#the-repos)
- [Features](#features)
- [What was removed from stock LineageOS](#what-was-removed-from-stock-lineageos)
- [What this will never have](#what-this-will-never-have)
- [Known issues and milestones](#known-issues-and-milestones)
- [Changelog](#changelog)
- [Installing](#installing)
- [Building](#building)
- [Contributing](#contributing)
- [Special thanks](#special-thanks)

---

## What this is

A daily-usable LineageOS 18.1 build for the GPD XD+, running on a **kernel built from public GPL source** and driving the PowerVR GX6250 with hardware acceleration — OpenGL ES and Vulkan both. Controller, D-Pad, Wi-Fi, Bluetooth, audio, microphone and sensors all work.

The device is configured as a **SIM-less, camera-less handheld**, because that's what it physically is.

**The bootloader stays locked, and that is not a limitation here.** This is a 2018 MediaTek device, not a modern one: the SoC's boot ROM download mode is wide open, so every partition can be read and written over USB regardless of the lock state — the lock only means `fastboot flash` is refused. Installs go through TWRP, kernel changes go through `dd`, and a device that will not boot at all comes back over the preloader. Nothing in this port needs an unlocked bootloader, and unlocking was never attempted because there is nothing to gain from it. [`docs/INSTALL.md`](docs/INSTALL.md) explains the whole procedure.

## Why this exists

The XD+ was abandoned twice over.

**GPD** shipped it on Android 7.0 in 2018 and stopped there. **The community** got it as far as an unofficial LineageOS 18.1 in 2021 — and then that stopped too, parked at a "Beta 19" build whose **sources were never published**, despite the kernel being GPL-licensed. There is no source tree to fork, no bug tracker, no way for anyone else to pick it up. The one modern OS the device had was a binary drop with a dead end behind it.

Meanwhile the hardware is *fine*. A 5" 720p handheld with real shoulder buttons and analog sticks, an MT8176 and a GX6250. It still plays everything up to and around the sixth generation comfortably, which is the entire reason anyone owns one; game streaming is also great despite its lower-end Wi-Fi 2.4GHz specs.
What it needed was not more horsepower, but rather an OS from this decade, with sources anyone can pick up and rebuild.

So, this port starts from the old public GPL kernel tree and reconstructs the rest: device tree written from scratch, vendor blobs re-derived, every framework fix carried as a readable numbered patch instead of a fork. Everything needed to rebuild this ROM is public, **and stays public**.

## A note on how this was built

Honesty up front: this is a **side project, and it is substantially "vibecoded" with Claude**. Long reverse-engineering sessions, register dumps, HAL archaeology and patch-writing were done with heavy AI assistance, deliberately; it is the only reason a project of this size fit into spare time at all.

What that means for you:

- Everything published here is **tested on real hardware**. Nothing ships on the strength of "it compiled".
- The reasoning behind each fix is written down, because it had to be.
- But this is not a maintained, SLA-backed ROM. It is one person and a language model keeping an old handheld alive. Expect the pace of a hobby, not a distro.

## The repos

| Repo | Contains | Status |
| --- | --- | --- |
| [`android_device_gpd_xdplus`](https://github.com/Keyaku/android_device_gpd_xdplus/tree/lineage-18.1) | Device tree — board config, product makefiles, HAL manifest, overlays, `rootdir/`, the `patches/` set | `lineage-18.1` |
| [`android_vendor_gpd_xdplus`](https://github.com/Keyaku/android_vendor_gpd_xdplus/tree/lineage-18.1) | Proprietary blob set, and the script that bakes the vendor image from it | `lineage-18.1` |
| [`android_kernel_mt8176_common`](https://github.com/Keyaku/android_kernel_mt8176_common/tree/xdplus-los18) | 3.18.79 kernel source (GPL), forked from the published `mt8176_common` BSP | `xdplus-los18` |
| [`android_device_gpd_xdplus_recovery`](https://github.com/Keyaku/android_device_gpd_xdplus_recovery/tree/android-11) | TWRP 3.7.0_11-0 device tree, built on the `twrp-11` base with this port's kernel | `android-11` |

Only branches for versions actually supported are carried. For the ROM trees that means **`lineage-18.1`** and nothing else; an empty `lineage-20` branch would just waste your afternoon. The recovery tree tracks the OS it services, not TWRP releases, so its branch is named after the Android version.

## Features

### The platform

- **LineageOS 18.1 / Android 11**, up from the stock Android 7.0, a four-version jump on 2018 vendor blobs.
- **Kernel built from source** (3.18.79) rather than lifted from a shipped image, including an Android-11 binder ABI backport the 2019-era GPL tree predates.
- **Release-signed** builds; upstream framework changes carried as **27 numbered patches** with per-patch rationale, not as forks of `frameworks/*`.

### Graphics

- **Hardware GPU** — PowerVR GX6250 on the DDK 1.9 driver stack.
- **OpenGL ES** works throughout the UI and in apps.
- **Vulkan (1.0) works in games** (needs more testing), via a compatibility shim that works around the driver's crashes. RetroArch and its cores run on the Vulkan renderer. Flutter apps requiring Vulkan 1.1 are funneled through backwards compatibility extensions; they'll work, but don't expect full Vulkan 1.1 support.
- **Rotation flat-pose handling** — the accelerometer sits in the clamshell base, so resting the device on a table reads as "flat" and stock Android freezes the last orientation. A configurable rotation is proposed instead.
- **Landscape by default** — the panel is mounted portrait, so the display itself is rotated to landscape below the window manager. The device comes up landscape from the setup wizard onwards, with no per-user settings to apply after a wipe, and the boot animation plays landscape too. Touch and the accelerometer are rotated to match, so auto-rotate is correct rather than a quarter turn out. ⚠️ **It arrives with the vendor image**, so an update over OTA alone does not carry it — flash the vendor zip published beside the release.

### Audio

- **Microphone capture fixed.** Faults in the Android 8.1-era vendor audio HAL were worked around; the stock recorder and third-party apps record real audio.
- **Headset jack plumbed.** Polling the driver's own sysfs state restores routing, speaker mute and the status-bar icon. _Headset mic can be detected_, but is deliberately ignored due to hardware limitations (needs more research into the audio stack).
- Hardware video codecs, and low-latency audio suitable for **Moonlight** game streaming.

### Input

- **D-Pad fixed** — a key layout that the build system was quietly overwriting with a generic one.
- Full controller support: sticks, shoulders, face buttons, D-Pad.

### Connectivity

- **2.4 GHz 802.11n & 5 GHz 802.11ac**.
- **Power-save handled by screen state.** The MT6630 driver mishandles 802.11 power-save and access points kick the device under sustained load, so the radio is kept awake while the screen is on and allowed back into power-save when it is off. Pinning it off unconditionally was the first fix and cost real standby battery; making it screen-conditional keeps the link stable in use without paying for it idle.
- **Bluetooth 4.1**, with pairing and A2DP audio.
- **Both radios patched**: Wi-Fi and Bluetooth are each fixed in their own right and can run together. _Yes, I know: insanity!!_
- The only Wi-Fi gap is **WPA3/SAE**, below.

### Security and system

- **TEE-backed keymaster and gatekeeper**, preferred over the software fallback and taught to accept the trustlet's non-standard password handle — which is what makes a **PIN** and hardware-backed keys work at all.
- **Widevine DRM HAL** brought up on the 8.1-era blobs, working around a symbol rename between Android 8 and 11 that crash-looped the service.
- Init hardened against pre-Android-9 vendor behaviour — without those guards init segfaults on boot, `logcat` is dead, and netd starts with no network at all.
- An in-Settings **"GPD XD+"** menu exposing device-specific toggles at runtime.
- Boot time cut to ~30 s — which honestly surprises me given the hardware.

## What was removed from stock LineageOS

- **The Camera app** and the camera feature flags. The XD+ has no camera; advertising one only makes apps fail confusingly. **Camera blobs** were also stripped from the vendor partition entirely.
- **Telephony is dormant.** The packages stay (Settings depends on them), but there is no radio HAL and the device declares itself non-voice-capable.
- **Four sensors the device does not have.** Stock declared a gyroscope, a compass, an ambient light sensor and a proximity sensor — claims inherited from MediaTek's reference tablet design and carried through GPD's own firmware, which shipped a gyroscope flag on a kernel that had no gyroscope driver compiled in at all. None of the four parts answers on the i2c bus. The feature flags are gone, and the two that the closed vendor software also invented in its own sensor list are patched out of it, so nothing can register a listener that will never receive a sample. The accelerometer is real and untouched.
- **The adaptive brightness switch**, which needed the ambient light sensor that is not fitted. It could only ever leave brightness where you had set it.
- **No Google apps.** Standard LineageOS: nothing Google ships is included. Install GApps or microG yourself if you want them.

## What this will never have

Not "not yet" — these are hardware or licensing walls with nothing behind them.

- **Cellular / SIM.** No modem in the device.
- **Camera.** No sensor in the device.
- **Gyroscope, compass, ambient light and proximity sensors.** None of them is fitted. Motion controls that need a gyroscope cannot work here; the accelerometer covers screen rotation and nothing more.
- **`fastboot flash` / `fastboot boot`.** GPD never provided an unlock path for this model, and the lock is what refuses those two commands. Everything they would be used for is covered by TWRP and the preloader instead, so this costs convenience rather than capability.
- **Widevine L1.** L1 needs a certified, provisioned OEMCrypto path through the TEE, which this device was never issued. Protected HD streaming from services that require L1 will not happen here.
- **Google Play certification.** Uncertified builds, by construction.
- **6 GHz Wi-Fi.** No 6E radio, despite what "hardware info" apps claim.
- **A from-source `/vendor` image.** The device uses the legacy system-as-root layout where `/vendor` is a symlink into the system image, and building one natively creates a mount loop. Vendor stays a partition-based blob set, injected post-build.
- **Anything requiring drivers that don't exist.** The GPU, Wi-Fi and video blobs are Android 8.1-era binaries with no source, and there will never be newer ones. That is the ceiling every future Android version has to be dragged over.

## Known issues and milestones

### Known issues

- **mini-HDMI output has rough edges.** Mirroring works, survives fullscreen apps, comes up on its own when you plug a cable in and carries sound — but bring-up occasionally needs a retry (reboot if it fails twice), opening an app after the device has sat idle a while can freeze both pictures, and an app that forces a portrait screen can leave the built-in one wrong. "Tear down HDMI" in the GPD XD+ menu is the way out of both freezes. Games also run less smoothly while a monitor is attached, which is inherent to the way this chip mirrors.
- **WPA3 / SAE will not connect.** The limit is in the closed-source MT6630 driver and firmware, not in the framework.
- **SELinux runs permissive.** The device policy exists and enforcing has been verified with graphics, Vulkan, gameplay, codecs, Bluetooth, Wi-Fi and the Settings menu all working, but it is **not the default** and one blocker remains: the vendor sensor service is denied access to the accelerometer under enforcing, which silently disables auto-rotate until a reboot.
- **Turning on `/data` encryption requires erasing `/data`.** Encryption ships and works, but there is no in-place conversion — an existing install has to be wiped to take it.
- **The vendor partition is updated by a separate zip.** An update carries the system and the kernel only, so features that straddle the two — landscape by default, the sensor list, HDMI audio — need the vendor zip published beside the release. Installing without it is refused rather than half-applied.
- **Vulkan is 1.0.** The 2017 driver supports 1.0 completely and nothing newer; apps that require 1.1 or later, PCSX2 among them, need to stay on OpenGL.
- **Widevine is brought up but only L3 is expected to work**, and L3 has not been verified against a real DRM service.

### Milestones

Roughly in the order they are likely to be attempted: make SELinux enforcing the default, which needs the sensor denial above solved; smooth out HDMI bring-up and the composer-side freeze that the mirror currently works around; and pushing the port up the LineageOS versions as far as 8.1-era blobs can be dragged.

One quirk is worth stating up front, because it looks like a bug and is not:

- **The "Gamepad Mapper" button does nothing, by choice.** On stock it opened GPD's own key-remapping overlay, which is not part of this port, so the button has no owner here. Rather than give it an unrelated job, it is left inert for this release: the key layout maps it to an otherwise-unused keycode so that a future feature can claim it cleanly. Giving it a real purpose is planned, and it is the only hardware control on the device that currently has no effect.

## Changelog

[`docs/changelog/`](docs/changelog/) — one file per release, newest first.

The current release is [20260817](docs/changelog/20260817.md) — encrypted `/data`, landscape by default, HDMI mirroring with sound, updates that install themselves, and a device SELinux policy. Work finished after it is listed under [Unreleased](docs/changelog/unreleased.md).

## Installing

Short version, on a device that already has TWRP:

```sh
./scripts/install.sh lineage-18.1-<date>-UNOFFICIAL-xdplus.zip
```

That routes the device into recovery, verifies the transfer, installs, clears the boot control block and reboots.

Long version — and you should read it, because the locked bootloader makes this device unlike whatever you flashed last — is **[`docs/INSTALL.md`](docs/INSTALL.md)**. It covers semi-automated installs, TWRP installs, SP Flash Tool for first-time setup and unbricking, keeping Magisk across updates (the zip overwrites your kernel), and troubleshooting.

Releases are published under [Releases](https://github.com/Keyaku/gpd-xdplus-customrom/releases).

## Building

You need a LineageOS 18.1 source tree. Point `repo` at the device tree with a local manifest:

```xml
<!-- .repo/local_manifests/xdplus.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="Keyaku/android_device_gpd_xdplus"
           path="device/gpd/xdplus"
           remote="github"
           revision="lineage-18.1" />
</manifest>
```

```sh
# fetch the device tree first, then let its local manifest pull kernel + vendor
mkdir -p .repo/local_manifests
cp device/gpd/xdplus/local_manifests/xdplus.xml .repo/local_manifests/
repo sync
source build/envsetup.sh
lunch lineage_xdplus-userdebug
# apply the numbered patches from device/gpd/xdplus/patches/ (see its README)
brunch xdplus        # → flashable zip
```

The scripts in [`scripts/`](scripts/) wrap the device-specific parts: `build.sh`, `flash.sh`, `bootcheck.sh`, and `inject_vendor.sh` for producing a vendor-writing zip. They read their paths from `scripts/env.sh` — set `XDROOT` in a local `scripts/xdplus.env` and nothing else is machine-specific. See [`scripts/README.md`](scripts/README.md).

Two things that will waste your day if you skip them:

- `breakfast xdplus` does **not** fetch anything here. LineageOS's roomservice hardcodes `LineageOS/<repo>` as the source of every `lineage.dependencies` entry (`vendor/lineage/build/tools/roomservice.py`), and these repos are not under that org — hence the local manifest above, which is also what puts the kernel at the path `TARGET_KERNEL_SOURCE` expects.
- The kernel is built in-tree by `mka bacon`, from `mt8176_defconfig` plus `arch/arm64/configs/xdplus_kernel.frag`. Without that fragment the DDK version drops to 1.7 against 1.9 blobs and SurfaceFlinger loops forever on `PVRSRVConnectKM: Incompatible driver` — and `kernel.mk` only warns about a missing fragment, so verify the deltas landed in `out/target/product/xdplus/obj/KERNEL_OBJ/.config` before flashing.
- `mka bacon` writes the **boot** partition too. Every system flash silently replaces the running kernel.

TWRP is built separately, from its own tree on the `twrp-11` minimal manifest rather than in this tree — see [`android_device_gpd_xdplus_recovery`](https://github.com/Keyaku/android_device_gpd_xdplus_recovery/tree/android-11). It takes the `Image.gz-dtb` this build produces, so build the ROM first.

## Contributing

Realistically, nobody is going to contribute to a forgotten handheld from 2018. That's fine; this exists so the option isn't closed.

If you do want to: issues and pull requests are welcome on any of the [component repos](#the-repos). Bug reports are genuinely useful even without a fix attached, especially with a `logcat` and what you were doing. If you have an XD+ and something in the [feature list](#features) doesn't work for you, that is worth knowing.

The one thing worth asking: keep fixes as **readable patches with a written rationale**, the way the existing `patches/` set does. This device only got this far because someone before could read what was changed and why — and never publishing that is exactly how it got stuck in the first place.

## Special thanks

To the people who published their work, which is the only reason any of this was possible:

- **[wuxianlin](https://github.com/wuxianlin)** — the ALLDOCUBE X (`u1005`) [device](https://github.com/wuxianlin/android_device_cube_u1005) and [vendor](https://github.com/wuxianlin/android_vendor_cube_u1005) trees. Another MT8176 device with the same blob lineage, and the definitive reference for every vendor-facing kernel interface on this SoC. Repeatedly the difference between a fixed bug and a mystery.
- **[druchaty](https://github.com/druchaty)** — the [`lineageos_kernel_cube_u1005`](https://github.com/druchaty/lineageos_kernel_cube_u1005) tree, the matching kernel side of the same reference.
- **[Goayandi](https://github.com/Goayandi)** — an independently published [`mt8176_common`](https://github.com/Goayandi/android_kernel_mt8176_common) tree of the same `wisky8176` BSP, invaluable for diffing to isolate what a given tree had modified.
- **The Chromium OS project** — the PowerVR 3.18 kernel work, a genuine reference for driving this GPU family on a kernel this old.
- **LineageOS** — for eleven years of keeping devices alive past their vendors, and for a build system that a single person can actually port with.
- **TeamWin** — TWRP, which on a locked-bootloader device is not a convenience but the only writable path onto the hardware.
- **topjohnwu** — Magisk.

### On the prior 18.1 work

A note rather than a credit, because accuracy matters here.

The XD+ had an earlier unofficial Android 8.1 ROM titled CleanROM, and the GPL trees published alongside the older Android 8.1-era work — the `mt8176_common` kernel and the TWRP tree — were real and useful, and this port builds on both. They are forked with history and attribution intact, as the GPL asks.

The 15.1-18.1 builds are a different matter _because they were locked behind a paywall_, distributed as flashable binaries and abandoned at Beta 19 over 5 years ago, unfinished (namely Vulkan and HDMI implementations were incomplete), and **the kernel sources were never published** — which the GPL **does not permit** for a binary you distribute. The practical result is that everyone running it was stuck: no source, no way to fix a bug, no way to continue the work. That is the gap this project exists to close, and it is why the kernel here is built from public source and why every framework change is carried as a readable patch. The published work is acknowledged. The unpublished part is not something to thank anyone for.
