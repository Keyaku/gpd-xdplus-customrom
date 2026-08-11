# Unreleased

⚠️ **Nothing on this page is in a published build yet.** It is done, committed and verified on hardware, and it ships in the next release. The current download is still [20260804](20260804.md).

## SELinux

The port now has a device policy, and enforcing mode works. **It is still not the default** — the build ships permissive, exactly as [20260804](20260804.md) did — but `setenforce 1` is now something the device survives with the whole feature set working, which was not true before.

- **Enforcing was impossible until now, for a reason nobody had looked at.** The kernel this port inherited clamped every write to `/sys/fs/selinux/enforce` to zero: no error, no audit record, the write reported success and enforcement stayed off. That clamp is gone.
- **Every service this port starts has its own SELinux domain.** Nine daemons of our own plus the OEM's `autokd`, which shipped with no domain at all — all of them used to run as `init` itself.
- **The graphics stack works under enforcing.** The largest group of denials turned out not to be missing permissions at all but an ioctl filter that excluded the MediaTek GPU bridge; screenshots, Vulkan and a full game session all work with enforcement on.
- **So do the codecs** — video encode and hardware-accelerated playback both needed vendor-side rules that did not exist. Without them screen recording failed outright and playback stalled in the decoder.
- **So does the in-Settings "GPD XD+" menu**, verified by driving the real UI with enforcement on.
- Denials logged on a normal boot are down from 108 to 38, and the ones that remain are being classified rather than blanket-allowed.

**What is left before enforcing can be the default**: the remaining denials, a pass over the parts of the system this port has not exercised under enforcement yet, and a soak on a release build.

## Vulkan shader cache

- **Each app's shader cache now lives inside that app's own storage** instead of one shared directory. The old layout could not work under SELinux enforcement in either direction: an app is not allowed to write outside its own sandbox, and the privileged helper that pruned the shared directory is not allowed to delete files inside app sandboxes.
- **Practical effects.** A cache is counted against its own app's storage, is removed when you clear that app's data, and is reclaimed automatically by Android when storage runs low. The **per-app** size limit in the "GPD XD+" menu is unchanged; the **all-apps** limit is gone, because there is no shared directory left to limit.
- **"Clear shader cache" still works**, and still takes effect the next time each game starts — which was already true of the old version, since a running app holds its cache open until it exits.

## The "GPD XD+" menu is its own app now

- Nothing changes on screen: the menu is still reached from Settings, in the same place, with the same pages. It is built as a device app rather than as a modification of the Settings app, which is how device-specific settings are normally shipped — and it means the Settings app on this ROM is now stock.

## Fixes

- **Every button in the "GPD XD+" menu that performed an immediate action did nothing.** The dispatcher behind them was started with an empty command because of how init expands properties when it parses its configuration, so HDMI bring-up, HDMI teardown and the shader-cache wipe were all silently no-ops. Fixed.
- The port's privileged helper scripts are installed as proper executables rather than being run through the shell, which is what lets them run at all under enforcement.

## Under the hood

- The vendor partition image now carries this port's own SELinux rules, appended to the OEM policy when the image is built. The OEM's file is left untouched in source, so what was changed stays readable.
- The vendor image also carries the `autokd` label, so that daemon lands in its own domain from a clean flash.

## Encryption

`/data` is encrypted now. File-based encryption (FBE) is on, with a lock screen if you want one.

- **This was blocked by a kernel bug, not a missing feature.** The ext4 encryption support this port inherited was incomplete in one specific place: looking up a file inside an encrypted directory did not load that directory's key. A directory created on the first boot became unreachable on the next one — present in a listing, missing to everything else, and impossible to delete. The first boot after enabling encryption worked; every boot after it dropped to recovery. Three other Android kernels for this chip generation all contain the missing piece, and it has been ported across.
- **Verified the boring way**: eight consecutive reboots on a clean build, then a lock pattern enrolled, rebooted, and unlocked.
- **Root still works.** Magisk installs and runs on an encrypted device — an earlier note in this project claimed the two could not coexist, and that turned out to be the same kernel bug wearing a different hat.

⚠️ **Turning encryption on requires erasing `/data`.** There is no in-place conversion. If you are already running this ROM, moving to an encrypted `/data` means a clean wipe — back up anything you care about first.

## Updates install themselves now

**The Updater can apply an update on its own.** Pick the update, let it download, tap install — the device reboots into recovery, installs, and reboots back into the system with nothing to tap in recovery. Until now that hand-off did nothing: the device rebooted into recovery and sat at the menu, and the update had to be installed by hand.

- **The cause was a single missing line in recovery's partition table.** Android leaves a note for recovery in a small partition saying what to do on the next boot. Recovery could not find that partition, so it never read the note — and, worse, never cleared one either.
- **A leftover note used to send the device back into recovery in a loop.** Anything that had written one — an interrupted update, a failed boot — left it behind, and the only way out was clearing it by hand. Recovery now clears it whenever it reboots into the system.

⚠️ **Installing an update removes root.** That is true of any install, hand-flashed or automatic — reinstall Magisk afterwards if you use it.

## Recovery

- **TWRP no longer stores its own settings and logs on `/data`.** It cannot decrypt `/data`, so writing there was actively harmful once encryption was in play. It uses the microSD card instead. ⚠️ **Keep a card in the device** when using recovery on an encrypted device.

## Landscape by default

The device comes up landscape now — from the setup wizard onwards, with nothing to set by hand.

- **The display itself is rotated**, below the window manager, instead of the rotation being a per-user setting. That is what makes it apply to the setup wizard and survive a wipe: previously a clean install started portrait and needed auto-rotate turned off, a fixed rotation chosen, and a launcher preference edited, every time.
- **The boot animation is landscape too**, with no change to the animation itself — it draws through the same rotated display.
- **Touch follows the rotation.** The digitizer is wired portrait and the input system takes its orientation from the window manager, which no longer knows about the rotation, so the touchscreen driver now reports landscape coordinates directly. Without this, taps land transposed.
- **Auto-rotate is correct.** The accelerometer is mounted to the panel, so its idea of "upright" moved with the display and every rotation was a quarter turn out. Its mount orientation was corrected to match, and the flat-on-a-table pose returns to landscape rather than portrait.

⚠️ **This arrives with a vendor image, so it reaches clean installs and hand-flashed vendor partitions — not an update over OTA.** An OTA zip carries system and boot only. The vendor image is published as a second zip on the release page — flash it too.

## An update refuses to half-install itself

An update carries the system and the kernel, but not the vendor partition, so a feature split across the two could previously arrive halfway — landscape input against a portrait display, for instance, which is worse than not updating at all.

- **The build now checks the vendor partition before it writes anything.** If it is older than the build expects, the install stops with a message telling you to flash the vendor zip first, and nothing on the device has changed. Installing in the wrong order, or skipping the vendor zip, can no longer leave the device in a broken half-state.
- The same check runs whether you install by hand in recovery or let the Updater do it.

## Mini-HDMI: plug it in and it works

- **A cable connected before you switch the device on now brings the external picture up by itself**, with nothing to press. Previously the display driver could not notice a cable on an idle device at all, so the mirror had to be started from the "GPD XD+" menu.
- **Unplugging and replugging works too**, and the picture comes back on its own.
- **The picture appears in about half a second** once the device reaches the point of driving the monitor, instead of taking around nine. Two things were behind the old delay: the bring-up waited out fixed timers instead of waiting for the hardware, and it followed the monitor's own re-connection blink all the way down and back up — so the image appeared, vanished, and came back several seconds later. It now waits on the hardware and rides out the blink.
- **The mirror survives sleep**: the monitor goes dark with the device and the picture returns within a few seconds of waking it.

⚠️ Tearing HDMI down from the menu still leaves re-detection of the same cable disabled until the next reboot — unplugging and replugging is unaffected.

## The device no longer claims sensors it does not have

The XD+ has one sensor: the accelerometer. It was nevertheless advertising a gyroscope, a compass, an ambient light sensor and a proximity sensor — four claims inherited from MediaTek's reference tablet design and carried, unchanged, through the original GPD firmware.

- **Those four are no longer advertised.** An app that requires any of them now correctly skips this device, or hides the feature, instead of installing and then finding nothing there.
- Games and apps that merely *offer* motion controls are unaffected — they were already falling back to the buttons, because there was never a gyroscope to read.

⚠️ The system's own sensor list, which comes from the closed graphics-era vendor software, still mentions a light and a proximity sensor. That cannot be corrected from our side, and nothing reads them.
