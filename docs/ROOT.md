# Root, with Magisk

Releases are **`user` builds** — the same variant a shipped phone runs. That is deliberate: a release should not carry a debuggable, `adb root`-able system just because the people who built it found that convenient.

**It does not stop you rooting the device.** Magisk is a separate mechanism from the build variant and works exactly the same on a `user` build. What the variant changes:

| | `user` (releases) | `userdebug` (development) |
| --- | --- | --- |
| Magisk root, `su` for apps and shells | ✅ works | ✅ works |
| `adb root` | ❌ refused | ✅ works |
| `ro.debuggable`, ptrace/debug any app | 0 | 1 |
| Serial `console` service on `/dev/console` | not started | started |

`adb root` is refused because **adbd itself checks `ro.debuggable`** and answers "adbd cannot run as root in production builds". No root solution changes that, because adbd is not asking one. With Magisk installed you get the same reach through `adb shell su -c '…'`.

## Installing Magisk

You need TWRP, which you already have if you followed [INSTALL.md](INSTALL.md).

1. **Install the Magisk app.** Download `Magisk-vXX.apk` from [the official releases](https://github.com/topjohnwu/Magisk/releases) and install it like any APK.
2. **Get this release's `boot.img`.** It is inside the ROM zip you flashed — `unzip -o lineage-18.1-*-xdplus.zip boot.img`. ⚠️ It must be **the boot.img of the build you are actually running**. Patching a different one gets you a kernel that does not match your system.
3. **Copy it to the device** and, in the Magisk app, tap **Install → Select and Patch a File**, choose that `boot.img`, and let it write `magisk_patched-XXXXX.img` to `Download/`.
4. **Copy the patched image back to your PC**: `adb pull /sdcard/Download/magisk_patched-XXXXX.img`
5. **Flash it from TWRP.** Reboot to recovery, then either:
   - **Install → Install Image →** pick the patched image → choose the **Boot** partition; or
   - from your PC, with the device in TWRP:
     ```sh
     adb push magisk_patched-XXXXX.img /tmp/boot-magisk.img
     adb shell 'dd if=/tmp/boot-magisk.img of=/dev/block/platform/soc/11230000.mmc/by-name/boot'
     ```
6. **Reboot**, open the Magisk app, and confirm it reports itself installed. From a shell, `which su` should answer `/system_ext/bin/su`.

⚠️ **`fastboot flash` is not an option on this device** — the bootloader is locked and refuses it. Writing `boot` happens from TWRP, by `dd` or Install Image. This is the one habit from other Android devices that will waste your time here.

## ⚠️ Every ROM update removes root. Every time.

The ROM zip contains `boot.img` and writes it, so **installing an update replaces your Magisk-patched kernel with a clean one**. Root is gone until you patch again.

There is no `addon.d` script to save you: `/system/addon.d/` on this ROM holds only `50-lineage.sh`, and Magisk's `99-magisk.sh` is not installed, so the `backuptool` restore that preserves root on some devices has nothing to run here. This was mis-documented for a while during development and cost real time — treat "my root survived an update" as the surprise, not the norm.

**So after every ROM update**: repeat steps 2–6 with the *new* release's `boot.img`. Keep the patched image around; it is only valid for the build it came from.

**Check with `which su`, not by looking in `/system/bin` or `/sbin`.** On Magisk 24+ with Android 11 those directories are genuinely empty, and probing them reports a false negative. `su --version` or `su -c id` also work.

## If root disappears without an update

Occasionally `/system_ext/bin/su` goes missing after a boot that followed a crash or a hard recovery, while Magisk itself is still running. `/debug_ramdisk/su` still works in that state, and a reboot normally restores the usual path. If it does not, re-flash your patched boot image.
