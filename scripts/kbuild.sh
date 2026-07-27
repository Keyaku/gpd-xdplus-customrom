#!/bin/bash
# Build the 3.18 mt8176 kernel for xdplus, from the public GPL CleanROM-era tree.
# Baseline: mt8176_defconfig + arch/arm64/configs/xdplus_kernel.frag.
# Output: Image.gz-dtb under $KOUT/arch/arm64/boot/.
#
# This is the FAST-ITERATION path, not the shipping one: `mka bacon` builds the
# same kernel in-tree (device/gpd/xdplus/BoardConfig.mk TARGET_KERNEL_SOURCE).
# Both consume the same defconfig + fragment and produce an equivalent kernel;
# use this when a full bacon per kernel edit is intolerable.
set -u
source "$(dirname "$0")/env.sh"
KSRC=${KSRC:-$XDKSRC}
# The fragment is MANDATORY — without it CONFIG_MTK_GPU_VERSION is unset, the
# DDK drops to 1.7 against the 1.9 blobs, and SurfaceFlinger loops on
# "PVRSRVConnectKM: Incompatible driver". It lives inside the kernel tree so the
# in-tree build (kernel.mk resolves it under arch/$ARCH/configs/) and this
# script share one copy. Set KFRAG=/dev/null to deliberately build without it.
KFRAG=${KFRAG:-$KSRC/arch/arm64/configs/xdplus_kernel.frag}
TC=${TC:-$XDROOT/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-}
# Build on real disk, NOT a small tmpfs: a full out-tree plus gcc temps overflows
# anything under ~20G -> "Disk quota exceeded". gcc writes .s files to TMPDIR.
# Override KOUT/TMPDIR if $XDSTATE is not on a roomy filesystem.
KOUT=${KOUT:-$XDSTATE/kbuild/kout}
KLOG=${KLOG:-$XDSTATE/kbuild.log}
JOBS=${JOBS:-$(nproc)}
export TMPDIR=${TMPDIR:-$XDSTATE/kbuild/tmp}
mkdir -p "$KOUT" "$TMPDIR" "$(dirname "$KLOG")"
rm -rf "$KOUT"
mkdir -p "$KOUT"
export ARCH=arm64 CROSS_COMPILE="$TC"
# Modern host gcc (16.x) vs 3.18 host tools: -fno-common is the default since
# gcc 10, breaking dtc (duplicate `yylloc`). -fcommon restores old behavior.
# Must be a make cmdline arg: the 3.18 top Makefile assigns HOSTCFLAGS with `=`,
# which overrides the environment. Cmdline assignment wins over that.
HOSTFLAGS='HOSTCFLAGS=-Wall -Wmissing-prototypes -Wstrict-prototypes -O2 -fomit-frame-pointer -std=gnu89 -fcommon'
# Resolve KFRAG to an absolute path before cd'ing into the kernel source tree.
if [ -n "${KFRAG:-}" ]; then
	KFRAG="$(cd "$(dirname "$KFRAG")" && pwd)/$(basename "$KFRAG")"
fi
cd "$KSRC" || exit 2

{
	echo "=== KBUILD START $(date -Is) jobs=$JOBS ==="
	make O="$KOUT" mt8176_defconfig || { echo "KBUILD-FAIL defconfig"; exit 1; }
	if [ -n "${KFRAG:-}" ] && [ -f "$KFRAG" ]; then
		echo "=== merging fragment $KFRAG ==="
		./scripts/kconfig/merge_config.sh -O "$KOUT" "$KOUT/.config" "$KFRAG" || { echo "KBUILD-FAIL merge"; exit 1; }
	fi
	make O="$KOUT" -j"$JOBS" "$HOSTFLAGS" Image.gz-dtb headers_install 2>&1
	rc=$?
	if [ $rc -eq 0 ] && [ -f "$KOUT/arch/arm64/boot/Image.gz-dtb" ]; then
		echo "=== KBUILD-OK $(date -Is) ==="
		ls -l "$KOUT/arch/arm64/boot/Image.gz-dtb"
	else
		echo "=== KBUILD-FAIL rc=$rc $(date -Is) ==="
	fi
} 2>&1 | tee "$KLOG"
