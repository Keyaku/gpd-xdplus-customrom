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
# Clean, date-based build incremental. Without this the build system falls back to
# eng.$USER.$(timestamp), leaking your local username into ro.build.fingerprint.
# A bare YYYYMMDD.HHMMSS keeps per-build uniqueness (OTA delta detection) while
# dropping the username. Build stays userdebug/dev-keys on purpose (adb-root
# workflow); this only tidies the version string, it does not claim to be a
# signed user build. §93 vendor-thaw / fingerprint normalization.
export BUILD_NUMBER="$(date +%Y%m%d.%H%M%S)"
{
	source build/envsetup.sh
	lunch lineage_xdplus-userdebug
	mka bacon
} >> "$XDLOG" 2>&1
RC=$?

if grep -q 'build completed successfully' "$XDLOG"; then
	echo "BUILD-OK $(date -Iseconds)" >> "$XDLOG"
	exit 0
fi
echo "BUILD-FAIL rc=$RC $(date -Iseconds)" >> "$XDLOG"
exit 1
