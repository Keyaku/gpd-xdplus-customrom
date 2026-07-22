#!/bin/bash
# install.sh — install a GPD XD+ LineageOS 18.1 release onto a device that already
# has TWRP on its recovery partition.
#
# Standalone: does NOT need a LineageOS source tree, and does not source env.sh.
# All it needs is `adb`, `fastboot`, and the release zip you downloaded.
#
#   ./install.sh lineage-18.1-<date>-UNOFFICIAL-xdplus.zip
#   ./install.sh --boot boot.img lineage-18.1-<date>-UNOFFICIAL-xdplus.zip
#   ./install.sh --wipe lineage-18.1-<date>-UNOFFICIAL-xdplus.zip
#
# Options:
#   --boot <img>   also dd this boot.img to the boot partition after the zip.
#                  REQUIRED if you use Magisk: the zip writes boot too, so a plain
#                  install silently replaces your Magisk-patched kernel.
#   --wipe         factory reset (wipe /data + /cache) before installing. Needed
#                  when coming from another ROM or a different Android version.
#   --keep-adb     leave the device in recovery at the end instead of rebooting.
#   -y             don't ask for confirmation.
#
# This script does NOT flash TWRP and cannot install onto a stock device that has
# no TWRP. See docs/INSTALL.md for how to get TWRP on via SP Flash Tool first.
set -uo pipefail

BOOTIMG=""; WIPE=0; ASSUME_YES=0; KEEP_ADB=0; ZIP=""
while [ $# -gt 0 ]; do
	case "$1" in
		--boot)     BOOTIMG="$2"; shift 2;;
		--wipe)     WIPE=1; shift;;
		--keep-adb) KEEP_ADB=1; shift;;
		-y|--yes)   ASSUME_YES=1; shift;;
		-h|--help)  sed -n '2,25p' "$0"; exit 0;;
		-*)         echo "unknown option: $1" >&2; exit 2;;
		*)          ZIP="$1"; shift;;
	esac
done

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

# TWRP's kernel exposes the eMMC by-name links under a different node than the
# running system does. Try both, in TWRP order.
BYNAME_CANDIDATES="/dev/block/platform/soc/11230000.mmc/by-name /dev/block/platform/mtk-msdc.0/11230000.MSDC0/by-name"

# --- preflight ---------------------------------------------------------------
step "Checking prerequisites"
command -v adb      >/dev/null || die "adb not found. Install android-tools / platform-tools."
command -v fastboot >/dev/null || die "fastboot not found. Install android-tools / platform-tools."
[ -n "$ZIP" ]  || die "no release zip given. Usage: $0 [options] <release.zip>"
[ -f "$ZIP" ]  || die "release zip not found: $ZIP"
unzip -l "$ZIP" 2>/dev/null | grep -q 'META-INF/com/google/android/updater-script' \
	|| die "$ZIP does not look like a flashable ROM zip (no updater-script)."
if [ -n "$BOOTIMG" ]; then
	[ -f "$BOOTIMG" ] || die "boot image not found: $BOOTIMG"
	head -c 8 "$BOOTIMG" | grep -q 'ANDROID!' || die "$BOOTIMG is not an Android boot image (missing ANDROID! magic)."
fi
echo "zip        : $ZIP"
echo "boot.img   : ${BOOTIMG:-none, the kernel inside the zip will be used}"
echo "wipe /data : $([ $WIPE -eq 1 ] && echo YES || echo no)"

if [ -z "$BOOTIMG" ]; then
	echo
	echo "NOTE: installing the zip overwrites the boot partition. If this device is"
	echo "      rooted with Magisk, root will be LOST unless you pass --boot with a"
	echo "      Magisk-patched boot.img."
fi

if [ "$ASSUME_YES" -ne 1 ]; then
	echo
	echo "This will overwrite /system, /boot$([ $WIPE -eq 1 ] && echo ', and ERASE ALL USER DATA')."
	printf 'Continue? [y/N] '
	read -r ans
	case "$ans" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 1;; esac
fi

# --- route to recovery -------------------------------------------------------
step "Routing device to TWRP recovery"
if ! adb devices | grep -q 'recovery$'; then
	if adb devices | grep -q 'device$'; then
		echo "device is booted; rebooting to bootloader..."
		adb reboot bootloader 2>/dev/null
	fi
	# The bootloader is locked, so `fastboot flash` is refused — but the OEM
	# reboot-recovery command still works and is how we reach TWRP.
	for _ in $(seq 1 40); do fastboot devices 2>/dev/null | grep -q fastboot && break; sleep 3; done
	fastboot devices 2>/dev/null | grep -q fastboot \
		&& { echo "in fastboot; requesting recovery..."; fastboot oem reboot-recovery >/dev/null 2>&1; }
fi
for _ in $(seq 1 40); do adb devices | grep -q 'recovery$' && break; sleep 5; done
adb devices | grep -q 'recovery$' \
	|| die "device never reached TWRP. Boot it into recovery manually (power + volume) and re-run."
echo "TWRP reached."

# Resolve the by-name dir on this TWRP build once, and reuse it.
BYNAME=""
for c in $BYNAME_CANDIDATES; do
	adb shell "[ -d $c ]" >/dev/null 2>&1 && { BYNAME="$c"; break; }
done
[ -n "$BYNAME" ] || die "could not locate the by-name block device dir in TWRP."
echo "by-name    : $BYNAME"

# --- optional wipe -----------------------------------------------------------
if [ "$WIPE" -eq 1 ]; then
	step "Wiping /data and /cache"
	adb shell twrp wipe data  >/dev/null 2>&1
	adb shell twrp wipe cache >/dev/null 2>&1
fi

# --- push + verify -----------------------------------------------------------
step "Pushing the release zip ($(du -h "$ZIP" | cut -f1))"
H1=$(md5sum "$ZIP" | awk '{print $1}')
OK=""
for i in 1 2 3; do
	adb push "$ZIP" /sdcard/xdplus-install.zip >/dev/null 2>&1
	H2=$(adb shell md5sum /sdcard/xdplus-install.zip 2>/dev/null | awk '{print $1}')
	[ "$H1" = "$H2" ] && { OK=1; break; }
	echo "  md5 mismatch (attempt $i/3), retrying..."
	sleep 5
done
[ -n "$OK" ] || die "zip failed to transfer intact after 3 attempts."
echo "md5 verified: $H1"

# --- install -----------------------------------------------------------------
step "Installing (this takes a few minutes — do not unplug)"
adb shell twrp install /sdcard/xdplus-install.zip 2>&1 | tee /dev/stderr | tail -1 \
	| grep -q 'script succeeded\|Done processing' || die "TWRP reported the install failed."
adb shell rm -f /sdcard/xdplus-install.zip >/dev/null 2>&1

# --- optional boot.img -------------------------------------------------------
if [ -n "$BOOTIMG" ]; then
	step "Writing boot.img (post-zip, so it wins)"
	adb push "$BOOTIMG" /tmp/boot.img >/dev/null 2>&1 || die "failed to push boot.img"
	adb shell "dd if=/tmp/boot.img of=$BYNAME/boot bs=1M conv=fsync" 2>&1 | tail -2
	adb shell "dd if=$BYNAME/boot bs=8 count=1 2>/dev/null" | grep -q 'ANDROID!' \
		|| die "boot partition does not read back as an Android image. DO NOT REBOOT — reflash boot before leaving TWRP."
	echo "boot.img written and verified."
fi

# --- clear BCB + reboot ------------------------------------------------------
# Without this the bootloader keeps finding the recovery command in `para` and
# loops back into TWRP instead of booting the system.
step "Clearing the boot control block"
adb shell "dd if=/dev/zero of=$BYNAME/para bs=2048 count=1 conv=notrunc" >/dev/null 2>&1

if [ "$KEEP_ADB" -eq 1 ]; then
	echo; echo "Done. Device left in TWRP (--keep-adb)."
	exit 0
fi

step "Rebooting into the system"
adb shell twrp reboot system >/dev/null 2>&1
echo
echo "Done. First boot after a wipe takes ~1-2 minutes longer than usual."
echo "If it sits on the boot logo for more than 5 minutes, see docs/INSTALL.md"
echo "(Troubleshooting)."
