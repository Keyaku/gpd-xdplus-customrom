#!/bin/bash
# Route to recovery, push current zip (md5-verified, ≤3 retries), TWRP install,
# clear BCB (para), reboot to system. Does NOT rebuild. Returns 0 on flash OK.
source "$(dirname "$0")/env.sh"

# Route to recovery: system -> bootloader -> fastboot oem reboot-recovery.
if ! adb devices | grep -q 'recovery$'; then
	adb reboot bootloader 2>/dev/null
	for _ in $(seq 1 40); do fastboot devices 2>/dev/null | grep -q fastboot && break; sleep 3; done
	fastboot oem reboot-recovery >/dev/null 2>&1
fi
for _ in $(seq 1 40); do adb devices | grep -q 'recovery$' && break; sleep 5; done
adb devices | grep -q 'recovery$' || { echo "FLASH-FAIL: no recovery"; exit 2; }

H1=$(md5sum "$XDZIP" | awk '{print $1}')
OK=""
for i in 1 2 3; do
	adb push "$XDZIP" /sdcard/auto.zip >/dev/null 2>&1
	H2=$(adb shell md5sum /sdcard/auto.zip 2>/dev/null | awk '{print $1}')
	[ "$H1" = "$H2" ] && { OK=1; break; }
	sleep 5
done
[ -n "$OK" ] || { echo "FLASH-FAIL: md5 mismatch after 3 tries"; exit 2; }

adb shell twrp install /sdcard/auto.zip 2>&1 | tail -1 | grep -q 'script succeeded\|Done processing' \
	|| { echo "FLASH-FAIL: twrp install"; exit 2; }
# Clear BCB (the `para` partition) so LK doesn't loop straight back into recovery,
# then boot. Note the by-name path differs under the TWRP kernel from the one the
# running system uses, so try both.
adb shell "for BN in $XDBYNAME_TWRP $XDBYNAME; do dd if=/dev/zero of=\$BN/para bs=2048 count=1 conv=notrunc 2>/dev/null && break; done; twrp reboot system" >/dev/null 2>&1
echo "FLASH-OK $(date -Iseconds)"
exit 0
