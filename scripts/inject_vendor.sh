#!/bin/bash
# Turn a plain bacon zip (system+boot only) into a vendor-writing distributable.
#
# WHY THIS IS A SCRIPT AND NOT A BUILD FLAG: this device is legacy system-as-root,
# where /vendor lives inside the system image. BOARD_PREBUILT_VENDORIMAGE requires
# TARGET_COPY_OUT_VENDOR=vendor, which makes system/vendor a symlink -> /vendor
# (i.e. /vendor -> /vendor, a mount loop -> fastboot bounce). PORTING_LOG §46.
# So the build CANNOT emit vendor natively; we inject it post-bacon instead —
# the proven §42 recipe, automated.
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
# device has none); §60/§72 acqfd-patched hwcomposer (stock aborts on an unclosed
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
VIMG="${XDVENDOR_IMG:-$XDBACKUPS/vendor-slim-20260804.img}"
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

if grep -q 'by-name/vendor' "$US"; then
	echo "note: updater-script already writes vendor; leaving script as-is"
else
	# Insert the vendor write right after the system restore step (backuptool.sh
	# restore) so it lands before boot.img, matching the CAMFREE §42 ordering.
	LINE='ui_print("Writing vendor image...");'
	LINE="$LINE"$'\n''package_extract_file("vendor.img", "'"$XDBYNAME_TWRP"'/vendor");'
	awk -v ins="$LINE" '
		{ print }
		/backuptool\.sh", "restore"/ && !done { print ins; done=1 }
	' "$US" > "$US.new"
	grep -q 'by-name/vendor' "$US.new" || { echo "ERROR: failed to insert vendor write (no restore anchor?)" >&2; exit 3; }
	mv "$US.new" "$US"
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
unzip -p "$OUT" "$SCRIPT_PATH" | grep -q 'by-name/vendor' || { echo "ERROR: vendor write missing from script" >&2; exit 4; }

echo "OK -> $OUT"
