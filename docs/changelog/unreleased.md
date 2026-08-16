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

## Mirroring to a monitor no longer freezes in games

Mirroring to the mini-HDMI port used to stop dead as soon as a game or any other fullscreen app was in the foreground: the built-in screen kept working, the monitor froze on whatever was last on it, and it only came back when you left the app. It works through fullscreen apps now, with your animation speeds left alone.

- **The monitor stays live in games, videos and anything else fullscreen.** Nothing to turn on — it is on by default.
- **A new switch, "Keep the monitor alive in fullscreen apps"**, under GPD XD+ → Display out, in case you ever want it off. It takes effect immediately.
- It works by keeping one almost invisible pixel on screen while a monitor is plugged in. That is genuinely all it takes: the display chip's mirroring gives up when the screen contains a single thing to draw, and one more thing is enough to keep it going. The pixel disappears when you unplug.
- **Three switches are gone from Display out**, because they no longer do anything useful. "Turn off animations while mirroring" traded your animations for what this fix now does for free. "HDMI mirror mode" turned mirroring off entirely when disabled, and there is no reason to disable it. "Disable HDMI vsync pacing" was a debugging knob that displayed the wrong state.

Mirroring is still marked experimental: bring-up can fail and needs a retry, and **sound does not travel over the HDMI cable** — it keeps coming out of the handheld.

## Vulkan shader cache

- **Each app's shader cache now lives inside that app's own storage** instead of one shared directory. The old layout could not work under SELinux enforcement in either direction: an app is not allowed to write outside its own sandbox, and the privileged helper that pruned the shared directory is not allowed to delete files inside app sandboxes.
- **Practical effects.** A cache is counted against its own app's storage, is removed when you clear that app's data, and is reclaimed automatically by Android when storage runs low. The **per-app** size limit in the "GPD XD+" menu is unchanged; the **all-apps** limit is gone, because there is no shared directory left to limit.
- **"Clear shader cache" still works**, and still takes effect the next time each game starts — which was already true of the old version, since a running app holds its cache open until it exits.

## Vulkan driver identity

- **Hardware-info apps (DevCheck and friends) now see the Vulkan driver's real identity instead of "unknown" and all-zero UUIDs.** The vendor driver is Vulkan 1.0.49 from 2017 — it predates the Vulkan extensions those apps read (`VK_KHR_driver_properties`, the external-capabilities family), so the fields never had values. The port's Vulkan shim now advertises them and answers from the driver's own data: name "PowerVR Rogue", the real DDK build tag (`1.9@4893595`), and a driver UUID taken from the driver binary's own build ID, so it changes only if the driver binary changes.
- **"Driver conformance" still reads 0.0.0.0, and that is correct, not a leftover bug**: this GPU was never submitted for Khronos Vulkan conformance testing (every PowerVR entry on the conformant-products list is a newer Series8XE-or-later part), and 0.0.0.0 is the spec's defined "unknown / never submitted" value. There is no real number to show.
- **"Driver version" now reads 1.9.0** instead of "1.170.2971". The driver reports its Perforce changelist (4893595) in that field with no published encoding, and apps that guess the usual Vulkan bit-packing rendered it as a nonsense version; the shim now re-encodes it as the real DDK version. The changelist is still shown, in the driver-info string.
- Escape hatch: `debug.xdplus.vkdrvinfo=0` restores the old behavior.

## The "GPD XD+" menu is its own app now

- Nothing changes on screen: the menu is still reached from Settings, in the same place, with the same pages. It is built as a device app rather than as a modification of the Settings app, which is how device-specific settings are normally shipped — and it means the Settings app on this ROM is now stock.

## Fixes

- **Every button in the "GPD XD+" menu that performed an immediate action did nothing.** The dispatcher behind them was started with an empty command because of how init expands properties when it parses its configuration, so HDMI bring-up, HDMI teardown and the shader-cache wipe were all silently no-ops. Fixed.
- The port's privileged helper scripts are installed as proper executables rather than being run through the shell, which is what lets them run at all under enforcement.

## Kernel — CPU cluster sysfs layout modernized

- **`/sys/devices/system/cpu/cpufreq/policy0` and `policy4` now exist** (backported from Linux 4.7; 3.18 only exposed per-core `cpuN/cpufreq` dirs). Apps that enumerate CPU clusters by policy — MKM's CPU Clusters and Core Status sections among them — now show both clusters (quad A53, dual A72), their governors, frequencies and per-core state instead of empty sections.

## Kernel — battery current now exposed

- **`/sys/class/power_supply/battery/current_now` now exists**, backed by the fuel gauge's sense-resistor reading (µA, positive while charging). Monitoring apps previously had no standard current node at all and fell back to garbage (MKM showed charging power in the *thousands of watts* from an integer-overflow sentinel). Charge/discharge power now reads sanely (~0.5–1.5 W trickle-charging near full).

## Kernel — GPU now visible to monitoring apps

- **The GPU now registers with the kernel's devfreq framework** (`/sys/class/devfreq/mt8176-gpu`). Until now the GPU's frequency scaling ran entirely inside the MediaTek/PowerVR driver pair, so nothing in the standard sysfs location existed and kernel-manager apps (tested with MKM over Shizuku) showed the GPU's frequency, governor and frequency table as "Unknown"/"N/A". Those apps now show the live GPU frequency, the real OPP table (253.5–598 MHz) and the governor, and can set min/max frequency and governor through the standard nodes. The default governor is inert (`userspace`): the PowerVR driver's own frequency scaling is untouched unless a tool explicitly asks for a change.

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

## Mini-HDMI: a smoother picture, and windows that actually appear

- **The mirrored picture is smooth.** Playback and scrolling used to stutter on both screens while mirroring; that is gone.
- **Windows that open while mirroring now show up.** Pulling down the notification shade or quick settings could leave the screen looking untouched — the panel was still displaying the previous arrangement of windows on both the built-in screen and the monitor. Anything that changes which windows are on screen now appears as it should.

Both came from one fault in the display driver: while mirroring, changes to *which* windows are on screen and *where* they sit were prepared but never handed to the display hardware, which kept showing the last arrangement it had been given. Only the picture inside each window kept updating.

⚠️ **Rotating the screen while mirroring is still broken** — the picture freezes part-way through the turn on both screens, and tearing the mirror down and bringing it back is the way out. That is a separate fault, in the closed graphics software, and it is not fixed here.

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

- **The system's own sensor list is honest too.** The closed vendor software reported a light sensor and a proximity sensor that are not fitted. Both are filtered out before anything can see them, and they are now also patched out of the vendor software itself, so an app asking the system what sensors exist gets the one that is real.

⚠️ **The vendor-software half of that arrives with the vendor image**, not over an update — flash the vendor zip published beside the release. The filter alone is enough on a device that only takes the update.
- **Adaptive brightness is no longer offered.** It needs an ambient light sensor, so the switch could never do anything — it stayed on whatever brightness you had set. Brightness is manual, as it always effectively was.

## Deleting a large folder from the SD card works

Deleting a big folder from the SD card in the Files app used to show a "deleting" notification, run for a while, and finish with the folder still sitting there. No error appeared. Part of the folder's contents had usually gone.

Two separate causes, both fixed:

- **The SD card's filesystem was flushing to the card after every single file.** That is the safety setting Android uses on removable cards, and on a folder with tens of thousands of files it made deletion take minutes. It is now off for exFAT cards, which is what this device's card uses.
- **The system gave up on the storage service after 20 seconds** and killed it part way through, which is why the folder survived and nothing was reported. It now waits long enough for genuinely large jobs to finish.

A folder of 20,000 files now deletes in about 17 seconds, and the notification finishing means it is actually finished.

⚠️ **Eject the card properly** — through Settings, or the eject button next to the card in the Files app — before pulling it out. That was already true, but the card now keeps a little more in memory before writing it, so pulling it out mid-write has a slightly wider window to go wrong.
