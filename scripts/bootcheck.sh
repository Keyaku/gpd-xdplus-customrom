#!/bin/bash
# Verdict after a flash: wait for boot_completed, else dump a diagnosis bundle.
# Prints VERDICT: BOOT-COMPLETED | FASTBOOT-FALLBACK | STUCK (+ bundle).
source "$(dirname "$0")/env.sh"
DEADLINE=$(( $(date +%s) + 210 ))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
	if timeout 5 adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; then
		echo "VERDICT: BOOT-COMPLETED"
		adb shell 'getprop ro.lineage.version; dumpsys SurfaceFlinger 2>/dev/null | grep -m1 -i GLES'
		exit 0
	fi
	fastboot devices 2>/dev/null | grep -q fastboot && { echo "VERDICT: FASTBOOT-FALLBACK"; exit 2; }
	sleep 10
done

echo "VERDICT: STUCK (no boot_completed in 210s)"
adb logcat -d > "$XDBOOTLOG" 2>/dev/null
echo "--- fatal exceptions (system_server)"
grep -A4 'FATAL EXCEPTION IN SYSTEM PROCESS' "$XDBOOTLOG" | grep -E 'Caused by|Failed to' | sort -u | head -6
echo "--- native fatals (excl known keystore/gatekeeper)"
grep -E 'Fatal signal|Abort message' "$XDBOOTLOG" | grep -vE 'keystore|gatekeeperd' | tail -6
echo "--- top service waits"
grep 'Waiting for service' "$XDBOOTLOG" | awk '{print $NF}' | sort | uniq -c | sort -rn | head -4
echo "--- dlopen failures"
grep -oE 'dlopen failed: [^"]*"[^"]*"[^.]*' "$XDBOOTLOG" | sort -u | head -6
exit 1
