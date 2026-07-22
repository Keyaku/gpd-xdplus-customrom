# Installing LineageOS 18.1 on the GPD XD+

Read the whole of [Before you start](#before-you-start) before touching anything. The XD+ ships with a **locked bootloader, and this port assumes it stays locked**, which changes what "flashing a ROM" means on this device — several habits from other Android devices will brick you here.

- [Before you start](#before-you-start)
- [Which path do I need?](#which-path-do-i-need)
- [Path A — install via TWRP (normal case)](#path-a--install-via-twrp-normal-case)
- [Path B — SP Flash Tool (first-time and unbrick)](#path-b--sp-flash-tool-first-time-and-unbrick)
- [After the first boot](#after-the-first-boot)
- [Updating later](#updating-later)
- [Root (Magisk)](#root-magisk)
- [Troubleshooting](#troubleshooting)

## Before you start

**The bootloader is locked, and everything here assumes it stays that way.** Unlocking may well be technically possible on this hardware; it has not been attempted, and neither has re-locking, because the downside of getting it wrong is an unusable device. Nothing below needs an unlocked bootloader. Consequences you have to internalise:

- **`fastboot flash` does not work.** It is refused. Every partition write happens either from inside TWRP or from SP Flash Tool over the preloader.
- `fastboot oem reboot-recovery` **does** work, and is how the scripts reach TWRP.
- **Changing the kernel means `dd`, not flashing.** boot.img updates are written from a shell inside TWRP.
- **OTA auto-install cannot complete.** The Updater app downloads and verifies fine, but the reboot-and-apply step needs a bootloader the device doesn't have. Downloads still work; you install them by hand.

**You need TWRP on the recovery partition already.** This ROM's installer cannot put it there — TWRP itself comes from SP Flash Tool (Path B).

**Back up first.** `nvdata` and `nvram` hold your device's Wi-Fi/Bluetooth MAC addresses and calibration. If you erase them and have no backup, they are not recoverable from anywhere else. A full SP Flash Tool readback before you begin is cheap insurance.

**Requirements on the PC:** `adb` and `fastboot` (Android platform-tools). Path B additionally needs SP Flash Tool and, on Windows, the MediaTek VCOM/preloader drivers.

## Which path do I need?

| Your device right now | Path |
| --- | --- |
| Already running this ROM, or another ROM, **with TWRP installed** | [A](#path-a--install-via-twrp-normal-case) |
| Stock GPD Android 7, or any state without TWRP | [B](#path-b--sp-flash-tool-first-time-and-unbrick) first, then A |
| Bootlooping, but recovery still reachable | [A](#path-a--install-via-twrp-normal-case) with `--wipe` |
| Dead: no display, no adb, no fastboot | [B](#path-b--sp-flash-tool-first-time-and-unbrick) |

## Path A — install via TWRP (normal case)

### Scripted

From a checkout of this repo, with the device connected by USB:

```sh
./scripts/install.sh lineage-18.1-<date>-UNOFFICIAL-xdplus.zip
```

Coming from a different ROM or Android version, add `--wipe` — skipping the wipe across a major-version change reliably produces a bootloop:

```sh
./scripts/install.sh --wipe lineage-18.1-<date>-UNOFFICIAL-xdplus.zip
```

The script routes the device to TWRP, verifies the pushed zip by md5 (retrying up to three times — USB transfers to this device do occasionally corrupt), runs the install, clears the boot control block, and reboots.

### By hand

If you would rather drive TWRP yourself:

1. Boot to TWRP. From a running system: `adb reboot bootloader`, then `fastboot oem reboot-recovery`. Or hold **Volume Down + Power** from off.
2. If you are changing Android version or coming from another ROM: **Wipe → Format Data**, then wipe Cache.
3. Copy the zip over: `adb push lineage-18.1-*-xdplus.zip /sdcard/`
4. **Install** → select the zip → swipe.
5. Clear the boot control block before leaving recovery, or the bootloader will keep sending you straight back into TWRP:
   ```sh
   adb shell 'dd if=/dev/zero of=/dev/block/platform/soc/11230000.mmc/by-name/para bs=2048 count=1 conv=notrunc'
   ```
6. Reboot to system.

### ⚠️ The zip writes `boot` as well as `system`

This is the single most common way people lose root here. The build's `boot` image ships inside the zip, so installing it **replaces your kernel and removes Magisk**. If you are rooted, write your Magisk-patched boot.img back immediately afterwards, in the same TWRP session — see [Root (Magisk)](#root-magisk).

### `/vendor` and camera-free blobs

`/vendor` on this device is a real partition (`mmcblk0p23`) holding camera-stripped, prebuilt vendor blobs — the standard ROM zip does **not** touch it. If a release is published as a `-CAMFREE` zip, that variant additionally writes `vendor` and you install it exactly the same way. Install the plain zip on a device whose vendor partition is already correct; install the `-CAMFREE` zip when coming from stock or when a release note says the vendor set changed.

## Path B — SP Flash Tool (first-time and unbrick)

SP Flash Tool talks to the MediaTek **preloader** over USB, below Android and below the bootloader. It is the only way to install TWRP on a locked device, and the only way back from a device that shows nothing at all.

> **TODO:** this project does not yet publish its own SP Flash Tool package. It is a planned release artifact — a scatter set matching the layout below. Until then, use the SPFlash package of the previous unofficial 18.1 build for TWRP and for unbricking, then install this ROM over it via Path A.

A complete XD+ scatter package looks like this — `MBR`, `preloader.bin`, `lk.bin`, `logo.bin`, `tz.img`, `secro.img`, `boot.img`, `recovery.img`, `system.img`, `vendor.img`, `cache.img`, `userdata.img`, `nvdata.img`, `nvram.bin`, plus the `APDB_MT8173_*` database files and the scatter text file itself.

**Procedure:**

1. Install SP Flash Tool. On Windows also install the MediaTek USB VCOM / preloader drivers — without them the device enumerates for about two seconds and vanishes.
2. Load the **scatter file** from the package.
3. Choose the mode:
   - **Download Only** — writes just the checked partitions. This is what you want almost always.
   - **Firmware Upgrade** — writes everything including `preloader`. Only for a genuinely dead device, and only with a package that is known-good for the XD+.
   - **Format All + Download** — ⚠️ **never.** It erases `nvdata`/`nvram` and takes your Wi-Fi and Bluetooth MAC addresses with them.
4. **Uncheck `nvdata` and `nvram`** unless you are deliberately restoring your own backup of them. They are device-specific calibration, not ROM content.
5. To install *only* TWRP, uncheck everything except `recovery`.
6. Press **Download**, then connect the device **powered off** (hold Volume Up while plugging in if it does not enumerate). The flash begins on its own.
7. Wait for the green tick. Unplug, then boot to recovery to confirm TWRP came up.

Then continue with [Path A](#path-a--install-via-twrp-normal-case).

## After the first boot

First boot takes noticeably longer than usual — around a minute on top of the normal startup, and longer after a data wipe. The boot logo sitting there for a couple of minutes is expected; five is not.

A few settings do not survive a `/data` wipe and are worth restoring right away if you use them:

- adb root toggle (Developer options)
- Private DNS → **Off** — the default automatic mode causes connectivity stalls on this device's Wi-Fi stack
- AudioFX — disable it if you get distorted or silent playback

Wi-Fi re-provisions itself on first connect; nothing to do there.

## Updating later

The Updater app will find and download builds, verify them, and then stop: it cannot reboot-and-apply on a locked bootloader. Take the downloaded zip from `/data/lineageos_updates/` and install it via [Path A](#path-a--install-via-twrp-normal-case). No wipe is needed between builds of the same LineageOS version.

Remember the boot partition rule on every single update, not just the first: if you are rooted, re-write your Magisk boot.img afterwards.

## Root (Magisk)

Root lives in the boot image, and there is no `fastboot boot` escape hatch on a locked bootloader, so the loop is:

1. Install the ROM zip (Path A).
2. Pull the newly installed boot image out of the device, patch it with the Magisk app, or reuse a boot.img you patched earlier for this same build.
3. Write it back from TWRP:
   ```sh
   adb push boot-magisk.img /tmp/boot.img
   adb shell 'dd if=/tmp/boot.img of=/dev/block/platform/soc/11230000.mmc/by-name/boot bs=1M conv=fsync'
   ```
4. Verify before you reboot — a truncated write here is a brick that needs Path B:
   ```sh
   adb shell 'dd if=/dev/block/platform/soc/11230000.mmc/by-name/boot bs=8 count=1' | head -c 8
   # must print: ANDROID!
   ```

`scripts/install.sh --boot boot-magisk.img` does steps 2–4 for you, in the right order and with the readback check.

**Keep a known-good boot.img on your PC.** It is the difference between a two-minute recovery and an SP Flash Tool session.

## Troubleshooting

**It boots straight back into TWRP, every time.** The boot control block still holds a recovery command. Clear `para` (step 5 of the manual install) and reboot.

**It drops into fastboot instead of booting.** Usually a bad or partially written boot image. Get into recovery with `fastboot oem reboot-recovery` and `dd` a known-good boot.img back.

**Stuck on the boot logo for more than five minutes.** Reboot to recovery and check whether it is a boot failure or a black screen; if it happens right after switching Android versions, you skipped the data wipe — redo the install with `--wipe`.

**A blank screen is not necessarily a hang.** The device may simply be asleep. Press a button before diagnosing anything.

**`adb devices` is empty but the device is plugged in.** On Linux this is nearly always a udev permission problem rather than a device fault — check `lsusb` for a MediaTek `0e8d` device. If it is listed there, add a udev rule granting your user access to it.

**TWRP cannot mount `/data`.** It is encrypted or the format is not what TWRP expects. Format Data (not just wipe) from TWRP, accepting that this erases user data.

**Total brick — no display, no adb, no fastboot.** Not fatal on MediaTek. The preloader still enumerates on USB for a few seconds after connecting a powered-off device; go to [Path B](#path-b--sp-flash-tool-first-time-and-unbrick).
