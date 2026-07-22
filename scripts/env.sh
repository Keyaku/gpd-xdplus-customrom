#!/bin/bash
# Shared paths/env for the xdplus build + flash scripts. Source this, don't run it.
#
# Everything here is overridable from the environment or from a local `xdplus.env`
# file (gitignored) placed next to this script. Nothing is hardcoded to one machine.
#
#   XDROOT   LineageOS 18.1 source tree root (the dir holding build/envsetup.sh)
#   XDDEV    device tree                 (default: $XDROOT/device/gpd/xdplus)
#   XDOUT    build output for xdplus     (default: $XDROOT/out/target/product/xdplus)
#   XDZIP    zip to flash                (default: newest bacon zip in $XDOUT)
#   XDKSRC   kernel source tree          (default: $XDREPO/../android_kernel_mt8176_common)

XDSCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDREPO="$(dirname "$XDSCRIPTS")"
export XDSCRIPTS XDREPO

# Local, machine-specific overrides. Keep your XDROOT here instead of editing this file.
[ -f "$XDSCRIPTS/xdplus.env" ] && source "$XDSCRIPTS/xdplus.env"

: "${XDROOT:?set XDROOT to your LineageOS 18.1 source tree (see scripts/README.md)}"
export XDROOT
export XDDEV="${XDDEV:-$XDROOT/device/gpd/xdplus}"
export XDOUT="${XDOUT:-$XDROOT/out/target/product/xdplus}"
export XDKSRC="${XDKSRC:-$XDREPO/../android_kernel_mt8176_common}"

# Newest bacon zip by mtime. `mka bacon` writes a fresh date-stamped name every run,
# so a hardcoded date silently reflashes a stale build. The fallback keeps this file
# sourceable before the first build exists.
if [ -z "${XDZIP:-}" ]; then
	XDZIP=$(ls -t "$XDOUT"/lineage-18.1-*-UNOFFICIAL-xdplus.zip 2>/dev/null | head -1)
	[ -z "$XDZIP" ] && XDZIP="$XDOUT/lineage-18.1-UNOFFICIAL-xdplus.zip"
fi
export XDZIP

export XDSTATE="${XDSTATE:-$XDSCRIPTS/.state}"
export XDLOG="${XDLOG:-$XDSTATE/build.log}"
export XDBOOTLOG="${XDBOOTLOG:-$XDSTATE/bootcheck.log}"
mkdir -p "$XDSTATE"

# by-name block device path. NOTE: this differs between the running system and the
# TWRP recovery kernel — recovery exposes the MMC controller under a different node.
export XDBYNAME="${XDBYNAME:-/dev/block/platform/mtk-msdc.0/11230000.MSDC0/by-name}"
export XDBYNAME_TWRP="${XDBYNAME_TWRP:-/dev/block/platform/soc/11230000.mmc/by-name}"
