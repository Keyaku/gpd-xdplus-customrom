#!/bin/bash
# Incremental build. Truncates its own log FIRST (kills the stale-"build
# completed" race), writes a fresh BUILD-START marker, returns 0 on success.
# Blocks until done (run detached with setsid nohup if you want async).
source "$(dirname "$0")/env.sh"

: > "$XDLOG"
echo "BUILD-START $(date -Iseconds)" >> "$XDLOG"

cd "$XDROOT" || exit 3
export ALLOW_MISSING_DEPENDENCIES=true
export BUILD_BROKEN_DUP_RULES=true
# ccache, if the host has one. Android 10+ refuses a build-tree ccache and takes
# only a system-installed binary via CCACHE_EXEC; BoardConfigKernel.mk threads the
# same CCACHE_BIN into the kernel's CROSS_COMPILE, so this covers the in-tree
# kernel build as well as soong. Opt out with USE_CCACHE=0. Size the cache once
# with `ccache -M` — the default 5G is small for a full Android tree plus a kernel.
# NOTE: do not try to fix host-tool environment problems by exporting variables
# here. soong runs ninja with a filtered environment (build/soong/ui/build/ninja.go
# allowlist), so anything not on that list never reaches a build action. The
# mke2fs.conf/orphan_file failure that looks like it belongs here is fixed in
# system/apex/apexer/apexer.py instead (patch 0021).
if [ "${USE_CCACHE:-1}" != "0" ] && command -v ccache >/dev/null 2>&1; then
	export USE_CCACHE=1
	export CCACHE_EXEC="${CCACHE_EXEC:-$(command -v ccache)}"
fi
# Keep the builder's local account out of the shipped image (§93). Three separate
# leaks, all defaulted rather than forced: BUILD_NUMBER otherwise falls back to
# eng.$USER.$(timestamp) in ro.build.fingerprint, and soong fills ro.build.user /
# ro.build.host from the invoking account and machine name unless already exported
# (build/soong/ui/build/kati.go). No spoofing: the build stays userdebug/dev-keys on
# purpose for the adb-root workflow, this only withholds local account names.
#
# BUILD_NUMBER is a per-build timestamp again, and ro.build.version.incremental
# with it. It was pinned to a fixed release id for a while because
# Build.isBuildConsistent() compares ro.system.build.fingerprint against
# ro.vendor.build.fingerprint and raises "Internal problem with your device" on any
# mismatch — and the incremental is part of the fingerprint, so a per-build value
# guaranteed a mismatch against a frozen /vendor. That is fixed at the source now:
# ro.vendor.build.fingerprint is deliberately EMPTY in the vendor tree, and the
# check skips the comparison entirely when it is. The vendor partition is a frozen
# third-party blob set with no build identity of its own, so empty is the honest
# value; ro.vendor.xdplus.blobs records what it actually is.
#
# ⚠️ Do not put a fingerprint back in the vendor build.prop. A non-empty value that
# is not character-for-character equal to the system one brings the dialog straight
# back, and keeping them equal would mean re-baking and re-flashing the 400 MB
# vendor partition on every single build.
#
# Minutes, not just the date: several builds a day is normal here, and a date-only
# incremental would collide between them — which is exactly what made the pinned
# value useless as a discriminator. XDPLUS_RELEASE still overrides, for cutting a
# release with a chosen id.
export BUILD_NUMBER="${XDPLUS_RELEASE:-$(date +%Y%m%d%H%M)}"
export BUILD_USERNAME="${BUILD_USERNAME:-xdplus}"
export BUILD_HOSTNAME="${BUILD_HOSTNAME:-xdplus-builder}"
{
	source build/envsetup.sh
	lunch lineage_xdplus-userdebug
	mka bacon
} >> "$XDLOG" 2>&1
RC=$?

if grep -q 'build completed successfully' "$XDLOG"; then
	echo "BUILD-OK $(date -Iseconds)" >> "$XDLOG"
	# The kernel is built in-tree now, so its DTB is a build output like any other
	# and worth checking here. Reported, not fatal — flash.sh is the gate that
	# refuses to flash on a mismatch.
	DTB=$(xddtb_check); DTBRC=$?
	echo "$DTB" | tee -a "$XDLOG"
	[ $DTBRC -eq 0 ] || xdnotify "xdplus build OK but $DTB"
	xdnotify "xdplus build OK"
	exit 0
fi
# Failure must be visible on stderr, not only in the log. Everything above is
# redirected into $XDLOG, so a caller that pipes or captures this script (e.g.
# `./build.sh | tail`) otherwise sees completely empty output on a failed build
# — which reads exactly like a quiet success. Worse, a pipeline's exit status is
# the *last* command's, so `./build.sh | tail` reports 0 no matter what this
# script returns. Print the marker and the first real error so the failure is
# impossible to miss even when the exit status has been swallowed.
echo "BUILD-FAIL rc=$RC $(date -Iseconds)" | tee -a "$XDLOG" >&2
echo "--- first error in $XDLOG ---" >&2
grep -m1 -A12 '^FAILED:' "$XDLOG" >&2 || tail -20 "$XDLOG" >&2
xdnotify "xdplus build FAILED"
exit 1
