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
# Keep the builder's local account out of the shipped image (§93). Three separate
# leaks, all defaulted rather than forced: BUILD_NUMBER otherwise falls back to
# eng.$USER.$(timestamp) in ro.build.fingerprint, and soong fills ro.build.user /
# ro.build.host from the invoking account and machine name unless already exported
# (build/soong/ui/build/kati.go). A bare YYYYMMDD.HHMMSS keeps per-build uniqueness
# for OTA delta detection. No spoofing: the build stays userdebug/dev-keys on
# purpose for the adb-root workflow, this only withholds local account names.
export BUILD_NUMBER="$(date +%Y%m%d.%H%M%S)"
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
	xdnotify "xdplus build OK"
	exit 0
fi
echo "BUILD-FAIL rc=$RC $(date -Iseconds)" >> "$XDLOG"
xdnotify "xdplus build FAILED"
exit 1
