#!/bin/bash
# Turn a plain bacon zip (system+boot only) into a vendor-writing distributable.
#
# WHY THIS IS A SCRIPT AND NOT A BUILD FLAG: this device is legacy system-as-root,
# where /vendor lives inside the system image. BOARD_PREBUILT_VENDORIMAGE requires
# TARGET_COPY_OUT_VENDOR=vendor, which makes system/vendor a symlink -> /vendor
# (i.e. /vendor -> /vendor, a mount loop -> fastboot bounce; the device lands in
# fastboot instead of booting).
# So the build CANNOT emit vendor natively; we inject it post-bacon instead —
# the same recipe that was proven by hand, automated.
#
# Injects VIMG into the zip as vendor.img + adds a raw updater-script write to the
# vendor partition (same mechanism as boot.img), then re-signs whole-file with
# releasekey. Output verifies against /system/etc/security/otacerts.zip on device.
#
# Usage: inject_vendor.sh [--zip IN.zip] [--vendor-img VIMG] [--out OUT.zip]
#   defaults: --zip $XDZIP (newest bacon), vendor = camerafree backup,
#             out = <in basename>-CAMFREE.zip in $XDOUT
set -euo pipefail
source "$(dirname "$0")/env.sh"

ZIP="$XDZIP"
# The vendor image is now a BUILD PRODUCT of the tracked blob set, not a hand-baked
# artifact: regenerate it any time with
#   vendor/gpd/xdplus/build_vendor_image.sh -o "$XDBACKUPS/vendor-fromtree-<date>-mmcblk0p23.img"
# and point XDVENDOR_IMG at the result. That tree carries the blobs plus the
# ownership, modes, file capabilities and SELinux labels git cannot store; the
# script's --verify compares content and metadata against a reference image, and
# two bakes are byte-identical.
#
# Contents, all deliberate, and all reproduced by the bake: camera stripped (the
# device has none); acqfd-patched hwcomposer (stock aborts on an unclosed
# acquire fd); mic route fix in mixer_paths.xml; and a vendor build.prop whose
# fingerprint/date/security_patch read GPD/xdplus rather than ALLDOCUBE/U1005E,
# with ro.vendor.build.fingerprint pinned to a fixed release id instead of a build
# timestamp so it stays equal to ro.system.build.fingerprint across every rebuild
# (BUILD_NUMBER in build.sh is pinned to match). A per-build value there fails
# Build.isBuildConsistent() and raises the "Internal problem with your device"
# dialog on every boot. Bump the release id only when vendor CONTENT changes, not
# for metadata edits, and re-bake in the same operation.
#
# The superseded hand-baked chain is kept for provenance only:
# vendor-backup (stock) -> -camerafree -> -hwcpatched -> -gpdfp -> -gpdfp20260720.
# Default is the newest tree-baked image. The 20260729 (no suffix) image is the
# pre-empty-fingerprint bake: flashing it brings back the "internal problem with
# your device" dialog on every boot because its pinned ro.vendor.build.fingerprint
# no longer matches the per-build system fingerprint. 20260729b is the bake with
# the deliberately empty vendor fingerprint. If you re-bake, point this (or
# XDVENDOR_IMG) at the new output and verify the fingerprint line is empty.
# 20260804 is the slimmed bake: the OpenCL stack, the MediaTek RenderScript driver
# and the whole RIL cluster were dropped from the tracked blob set (unreachable on
# a SIM-less device with no public.libraries entry for libOpenCL.so), taking the
# tree from 141 MB to 73 MB. Pointing this back at an older image silently
# reinstates ~68 MB of dead blobs.
# 20260808 adds the SELinux labels for the ten paths the OEM image left with no
# security.selinux xattr at all. Same contents and same fs_config as 20260804 --
# labels are the only difference. Without them init cannot exec those binaries
# once SELinux goes enforcing, the graphics composer and allocator among them, and
# even under permissive they run with no domain transition.
# 20260809 adds two things and nothing else (build_vendor_image.sh --verify against
# the 20260808 image reports exactly these): an exec label for /vendor/bin/autokd,
# so the OEM's calibration daemon lands in its own domain instead of running as
# init; and this port's own SELinux rules, appended to the OEM's nonplat_sepolicy.cil
# when the image is baked. Those rules are what makes the codecs work under
# enforcement -- without them screen recording fails outright and video playback
# stalls in the decoder -- and they cannot live in the device tree, because every
# type they name is declared in that vendor policy and does not exist at build time.
# 20260809-fbe adds ONE line and nothing else: the /data entry in
# etc/fstab.mt8173 gains fileencryption=aes-256-xts:aes-256-cts:v1, turning on
# file-based encryption. Everything else is identical to the image above.
# 20260810 rotates the display itself: ORIENTATION_270 in build.prop, so the
# device is landscape from the boot animation and the setup wizard onwards
# rather than through a per-user setting. It also introduces
# ro.vendor.xdplus.rev, the marker the OTA asserts on so an update carrying only
# system and boot cannot half-apply a change that straddles the two partitions.
# 20260811 patches the sensors HAL: it returned a static list of three sensors,
# two of which -- an ambient light sensor and a proximity sensor -- are not
# fitted and answer nothing on i2c, yet accepted listeners that never received a
# sample. The returned count is the only edit. It carries NO revision bump on
# purpose: nothing on the system side depends on it, so asserting on it would
# refuse installs for nothing.
#
# !! THIS IMAGE IS NOT SAFE TO FLASH ONTO AN EXISTING INSTALL BY ITSELF !!
# FBE cannot be enabled in place. Flashing it over a device whose /data is
# already plaintext makes vold's init_user0 step fail, and a failed init_user0
# reboots the device into recovery -- repeatedly. Converting an existing install
# means wiping /data, which destroys every app and setting on it. It also needs a
# kernel carrying the ext4 encrypted-directory lookup fixes; an older kernel with
# this fstab fails the same way.
#
# So: use this image for a fresh install or a deliberate wipe-and-convert, and
# point XDVENDOR_IMG at vendor-selinux-addendum-20260809.img for an in-place
# vendor refresh on a plaintext /data. Every image below that one carries the
# same fstab line, so the warning applies to the default too.
# Default is the tree bake, which is the only image guaranteed to carry the rev the
# current build asserts. Pointing this at a backup silently ships an older rev.
VIMG="${XDVENDOR_IMG:-$XDROOT/vendor/gpd/xdplus/vendor.img}"
OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--zip)        ZIP="$2"; shift 2;;
		--vendor-img) VIMG="$2"; shift 2;;
		--out)        OUT="$2"; shift 2;;
		*) echo "unknown arg: $1" >&2; exit 2;;
	esac
done

[ -f "$ZIP" ]  || { echo "ERROR: input zip not found: $ZIP" >&2; exit 2; }
[ -f "$VIMG" ] || { echo "ERROR: vendor.img not found: $VIMG" >&2; exit 2; }
if [ -z "$OUT" ]; then
	base=$(basename "$ZIP" .zip)
	OUT="$XDOUT/${base}-CAMFREE.zip"
fi

SIGNAPK="$XDROOT/out/host/linux-x86/framework/signapk.jar"
CONSCRYPT="$XDROOT/out/host/linux-x86/lib64"
PK8="$XDDEV/keys/releasekey.pk8"
PEM="$XDDEV/keys/releasekey.x509.pem"
for f in "$SIGNAPK" "$PK8" "$PEM"; do
	[ -f "$f" ] || { echo "ERROR: missing signing asset: $f" >&2; exit 2; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
UNSIGNED="$WORK/unsigned.zip"
cp "$ZIP" "$UNSIGNED"

SCRIPT_PATH="META-INF/com/google/android/updater-script"
US="$WORK/updater-script"
unzip -p "$UNSIGNED" "$SCRIPT_PATH" > "$US"

# Rewrite the script: drop the vendor-revision gate and add the vendor write.
#
# The gate exists to stop a system-only package installing against a vendor
# partition it does not match. A package that writes vendor itself satisfies that
# by construction, and leaving the gate in would abort on exactly the from-stock
# installs this package is for. Its mount of /vendor must go with it: writing the
# block device underneath a mounted filesystem corrupts it.
python3 - "$US" "$XDBYNAME_TWRP" <<'PYEOF'
import re, sys

path, byname = sys.argv[1], sys.argv[2]
src = open(path).read()

if 'package_extract_file("vendor.img"' in src:
	print("note: updater-script already writes vendor; leaving script as-is", file=sys.stderr)
	sys.exit(0)

# Drop every complete statement testing is_mounted("/vendor") -- the mount and the
# revision gate -- by consuming to the semicolon that closes each one.
while True:
	i = src.find('ifelse(is_mounted("/vendor")')
	if i < 0:
		break
	depth, j = 0, i
	while j < len(src):
		if src[j] == '(':
			depth += 1
		elif src[j] == ')':
			depth -= 1
		elif src[j] == ';' and depth == 0:
			j += 1
			break
		j += 1
	src = src[:i] + src[j:]
src = re.sub(r'\n{3,}', '\n\n', src)

# Vendor lands after the system image and before boot.
write = ('ui_print("Writing vendor image...");\n'
         'package_extract_file("vendor.img", "%s/vendor");\n' % byname)
anchor = 'package_extract_file("boot.img"'
k = src.index(anchor)
src = src[:k] + write + src[k:]

open(path, 'w').write(src)
PYEOF

grep -q 'package_extract_file("vendor.img"' "$US" || {
	echo "ERROR: failed to insert the vendor write" >&2; exit 3; }
if grep -q 'is_mounted("/vendor")' "$US"; then
	echo "ERROR: the vendor-revision gate survived the rewrite" >&2; exit 3
fi

# Stage vendor.img + updated script into the unsigned zip.
cp "$VIMG" "$WORK/vendor.img"
( cd "$WORK" && zip -q "$UNSIGNED" vendor.img )
mkdir -p "$WORK/META-INF/com/google/android"
cp "$US" "$WORK/$SCRIPT_PATH"
( cd "$WORK" && zip -q "$UNSIGNED" "$SCRIPT_PATH" )

echo "signing (releasekey, whole-file)..."
LD_LIBRARY_PATH="$CONSCRYPT" java -Djava.library.path="$CONSCRYPT" \
	-jar "$SIGNAPK" -w "$PEM" "$PK8" "$UNSIGNED" "$OUT"

echo "verifying vendor payload present..."
unzip -l "$OUT" | grep -q 'vendor.img' || { echo "ERROR: vendor.img missing from output" >&2; exit 4; }
# Check for the write itself: 'by-name/vendor' also appears in the revision gate,
# so grepping for that passes on a package that never writes vendor at all.
unzip -p "$OUT" "$SCRIPT_PATH" | grep -q 'package_extract_file("vendor.img"' || {
	echo "ERROR: vendor write missing from script" >&2; exit 4; }
if unzip -p "$OUT" "$SCRIPT_PATH" | grep -q 'is_mounted("/vendor")'; then
	echo "ERROR: the vendor-revision gate survived into the output" >&2; exit 4
fi

echo "OK -> $OUT"
