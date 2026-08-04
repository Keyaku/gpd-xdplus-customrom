# Installing LineageOS 18.1 on the GPD XD+

Read the whole of [Before you start](#before-you-start) before touching anything. The XD+ ships with a **locked bootloader, and this port assumes it stays locked** — which changes the mechanics of flashing rather than making it risky. Two paths cover every situation, and the second one reaches the hardware even when nothing else does.

- [Before you start](#before-you-start)
- [Which path do I need?](#which-path-do-i-need)
- [Path A — install via TWRP (normal case)](#path-a--install-via-twrp-normal-case)
- [Path B — the preloader (first-time and unbrick)](#path-b--the-preloader-first-time-and-unbrick)
- [After the first boot](#after-the-first-boot)
- [Updating later](#updating-later)
- [Root (Magisk)](#root-magisk) — and [ROOT.md](ROOT.md)
- [Troubleshooting](#troubleshooting)

## Before you start

**The bootloader is locked, and everything here assumes it stays that way.** On this MediaTek SoC the lock is far less consequential than on a modern device: the boot ROM download mode is open, so [Path B](#path-b--the-preloader-first-time-and-unbrick) can read and write any partition over USB no matter what state the device is in. Unlocking would buy nothing that Path B does not already give, and has not been attempted. What the lock does change:

- **`fastboot flash` does not work.** It is refused. Every partition write happens either from inside TWRP or over the MediaTek preloader (Path B).
- `fastboot oem reboot-recovery` **does** work, and is how the scripts reach TWRP.
- **Changing the kernel means `dd`, not flashing.** boot.img updates are written from a shell inside TWRP.
- **OTA auto-install cannot complete.** The Updater app downloads and verifies fine, but the reboot-and-apply step needs a bootloader the device doesn't have. Downloads still work; you install them by hand.

**You need TWRP on the recovery partition already.** This ROM's installer cannot put it there — TWRP itself comes from [Path B](#path-b--the-preloader-first-time-and-unbrick).

**Back up first, and it is one command.** `nvdata`, `nvram`, `proinfo`, `protect1` and `protect2` hold your unit's Wi-Fi/Bluetooth MAC addresses, radio and sensor calibration and DRM keys. They exist nowhere else in the world — no download recovers them. `./scripts/xdplus-preloader.sh backup ~/xdplus-backup` saves them, plus `boot` and `recovery`, and writes nothing.

**On the device:** enable **Developer options → USB debugging** before you start, and accept the authorization prompt when you first plug into your PC. Releases are `user` builds, so adb is authorized rather than open. ⚠️ This only matters for the first hop — getting a *running* system into recovery. Once the device is in TWRP, recovery's own adb needs no authorization, which is why the install itself works even on a device that will not boot.

**Requirements on the PC:** `adb` and `fastboot` (Android platform-tools). Path B additionally needs [mtkclient](https://github.com/bkerler/mtkclient) and Python 3 — it runs natively on Linux, and needs neither SP Flash Tool, nor Wine, nor Windows VCOM drivers.

## Which path do I need?

| Your device right now | Path |
| --- | --- |
| Already running this ROM, or another ROM, **with TWRP installed** | [A](#path-a--install-via-twrp-normal-case) |
| Stock GPD Android 7, or any state without TWRP | [B](#path-b--the-preloader-first-time-and-unbrick) first, then A |
| Bootlooping, but recovery still reachable | [A](#path-a--install-via-twrp-normal-case) with `--wipe` |
| Dead: no display, no adb, no fastboot | [B](#path-b--the-preloader-first-time-and-unbrick) |
| Not sure what you are even holding | `./scripts/xdplus-preloader.sh identify` — read-only, answers it in one step |

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

## Path B — the preloader (first-time and unbrick)

Below Android, below TWRP and below the bootloader, the MT8176 boot ROM answers on **every** power-up, for a fraction of a second, whether or not the device can boot, show anything or reach adb. That window is how a stock device gets TWRP, and how a device showing nothing at all comes back.

Historically this meant SP Flash Tool, Windows and MediaTek VCOM drivers. **It no longer does.** [mtkclient](https://github.com/bkerler/mtkclient) speaks the same protocol natively, and `scripts/xdplus-preloader.sh` wraps it with this device's specifics.

This works because the XD+ boot ROM is completely unprotected — it reports `SBC`, `SLA` and `DAA` all disabled — so no signed loader and no exploit is involved.

### Setup

```sh
git clone https://github.com/bkerler/mtkclient
cd mtkclient && python -m venv .venv && .venv/bin/pip install -r requirements.txt
export XDPL_MTKDIR=$PWD
```

On Linux you need udev rules for the MediaTek VID (`0e8d`) or you must run as root; mtkclient ships them.

### 1. Find out what you have — read-only

```sh
./scripts/xdplus-preloader.sh identify
./scripts/xdplus-preloader.sh identify --board-check   # also reads lk
```

It reports the SoC, the partition table and which of two layouts you are on:

- **STOCK** — GPD's own layout. There is **no `vendor` partition**, and `boot`/`recovery` are 16 MB where this ROM needs 64 MB and 96 MB. Installing here needs the partition table rewritten first; see [the repartition problem](#the-repartition-problem).
- **XDPLUS** — already repartitioned for this ROM. Everything below works directly.

`--board-check` reads the `lk` partition and hashes it against GPD's own `lk.bin` for the **new ("VR") board**. GPD's published test is to look for `VR` in the build number under Settings → About tablet, which is useless for a device that cannot boot — and it is destroyed the moment you flash any custom ROM. The hash works offline, on a dark device, forever.

⚠️ If `identify` reports anything other than SoC `0x8176`, stop. The original GPD **XD** is a different device with a Rockchip SoC, and this ROM is not for it.

### 2. Back up what cannot be downloaded

```sh
./scripts/xdplus-preloader.sh backup ~/xdplus-backup
```

Saves `proinfo`, `nvram`, `nvdata`, `protect1`, `protect2` — your unit's MAC addresses, calibration and keys — plus `boot` and `recovery`, with md5sums. **Do this before anything else.** These partitions are unique to your device; if you lose them, no firmware download brings them back.

### 3. Write

```sh
./scripts/xdplus-preloader.sh install <dir>            # boot/recovery/system/vendor
./scripts/xdplus-preloader.sh restore ~/xdplus-backup recovery   # one partition back
```

The script writes only `boot`, `recovery`, `system` and `vendor`. ⚠️ **It never writes `preloader`, `seccfg` or the bootloader lock state, and no option makes it.** Those are the parts that are not recoverable — get them wrong and the device is finished — whereas any of the four it does write can simply be written again.

### ⚠️ The session always ends with the device looking dead

When a preloader session finishes — success or failure — the device stays parked in Download Agent mode: red LED, no adb, no fastboot, and **the power button appears not to work**. Nothing is wrong and nothing was written that you did not ask for.

**Unplug the USB cable first, then hold power for ~10 seconds.** The cable is the reason: with USB power present the chip re-powers straight back into the preloader, which is exactly what makes the button feel dead. `mtk reset` does not help — it will tell you to pull the cable.

Budget **one power cycle per operation.** `identify --board-check` needs two sessions, so it asks before the second.

### The repartition problem

A stock XD+ cannot receive this ROM as-is. The layouts differ from `boot` onward:

| | Stock GPD | This ROM |
| --- | --- | --- |
| `boot` | 16 MB | **64 MB** |
| `recovery` | 16 MB | **96 MB** |
| `system` | 3 GB | 2.6 GB |
| `vendor` | **absent** | **400 MB** |
| `cache` | 1.5 GB | 400 MB |

So a first-time install has to write a new partition table, which destroys everything on the device — including the calibration partitions if they are not backed up first.

This is exactly what SP Flash Tool's **"Format All + Download"** step did in the original install instructions for this ROM — that mode, and not `Download Only`, is what rewrote the table. The table itself comes from the **`MBR`** file in that package: a 17,408-byte blob holding the MBR plus the primary GPT. It has been checked against a live device and describes all 25 partitions exactly, `recovery` at 96 MB included. ⚠️ The package's scatter *text* file disagrees — it declares `recovery` as 64 MB — and it is the **blob** that is authoritative.

```sh
./scripts/xdplus-preloader.sh backup ~/xdplus-backup        # FIRST. always.
./scripts/xdplus-preloader.sh install <dir> --repartition --mbr /path/to/MBR
# power-cycle, then:
./scripts/xdplus-preloader.sh identify                       # must now say XDPLUS
./scripts/xdplus-preloader.sh install <dir>
```

The table is written to offset 0 of the user area, which is the `pgpt` partition. **It does not touch the preloader**, which lives in the eMMC boot area — so a bad table is recoverable by writing a good one from here.

⚠️ **This particular path has not been run end to end** — writing *partitions* is verified, writing the *partition table* is not, and they are not the same risk. It refuses a blob without a valid `EFI PART` signature, requires a typed confirmation, and destroys everything on the device including the calibration partitions. Back up first and verify the md5sums came out.

**One thing you must do that the tooling cannot do for you:** the original instructions had you read your *own* `nvram` and `nvdata` off the device and substitute them into the package before flashing, because "Format All" erases them and the package's copies belong to somebody else's device. `backup` is the equivalent step here — and afterwards, restore your own with `restore ~/xdplus-backup nvram` and `restore ~/xdplus-backup nvdata`. ⚠️ **Flashing a stranger's `nvram`/`nvdata` gives you their MAC addresses and their radio calibration.**

### ⚠️ Known limitation: `--repartition` is documented but untested

Everything else on this page has been run on real hardware. **`--repartition` has not**, and it is the one step a first-time install onto a stock device needs.

What that means in practice: the code exists, the partition-table blob it writes has been parsed and verified byte-exact against a running device, the target offset is the `pgpt` partition and provably not the preloader, and the operation refuses a blob without a valid GPT signature. What has *not* happened is anyone running it end to end and watching a stock device come back. It stays in the tree, documented and gated, rather than being quietly removed or quietly presented as ready.

**Why it is unlikely to be tested soon**: testing it honestly requires a device that is still on the stock layout, and the development device was repartitioned years ago by the original SP Flash Tool install. Verifying it would mean deliberately destroying a working device's layout to rebuild it. If you have a stock XD+ and are willing to try, that report would be genuinely valuable — back up first, and expect to fall back to SP Flash Tool if it goes wrong.

**If you would rather not be the first**: use the previous unofficial build's SP Flash Tool package once, exactly as its README describes ("Format All + Download", after reading back your own `nvram`/`nvdata`). That establishes the layout and puts TWRP on. Everything after that — this ROM, updates, recovery from a bad flash — is covered by tested paths.

### Status of each operation

| Operation | Writes? | Verified on hardware |
| --- | --- | --- |
| `identify` | no | ✅ yes |
| `backup` | no | ✅ reads are exact — a 96 MB partition read back md5-identical to a reference `dd` |
| `install` / `restore` | yes | ✅ **yes** — a 1 MB write landed byte-exactly, with every byte outside the written range unchanged |
| `install --repartition` | yes | ⚠️ **not yet** — implemented, blob validated against a live device, never executed |

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

**Releases are `user` builds**, the same variant a shipped phone runs — so no `adb root`, and no "Serial console enabled" notification. That does **not** stop you rooting: Magisk is a separate mechanism and works the same on a `user` build. Full instructions, including what the variant does and does not change, are in **[ROOT.md](ROOT.md)**.

The device-specific mechanics, in short. Root lives in the boot image, and there is no `fastboot boot` escape hatch on a locked bootloader, so the loop is:

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
