# xdplus kernel config deltas over mt8176_defconfig (HANDOFF §KERNEL unlocks).
# Merged via scripts/kconfig/merge_config.sh (set KFRAG=this file for kbuild.sh).
#
# Unlock 1 — input lag: Android task-profile CPU-affinity.
# Baseline has CGROUPS + CGROUP_CPUACCT + CGROUP_SCHED only.
CONFIG_CPUSETS=y
CONFIG_PROC_PID_CPUSET=y
# NOTE: CONFIG_CGROUP_SCHEDTUNE (EAS boost) is NOT available in this 2019
# CleanROM 3.18 tree — no SchedTune/EAS backport exists (grep: zero hits for
# schedtune/sched_tune anywhere). Enabling it would require backporting the
# whole EAS scheduler (heavy, boot-risk). CPUSETS above delivers the primary
# task-profile CPU-affinity fix; EAS boost is deferred to the mainline path.
# CONFIG_CGROUP_SCHEDTUNE=y  # unavailable, see above
#
# Unlock 2 — ALS/auto-brightness (LTR303): already =y in baseline, pinned here
# so the fragment documents the full intended set.
CONFIG_CUSTOM_KERNEL_ALSPS=y
CONFIG_MTK_LTR303=y
#
# Boot-critical (Android 11 Treble): the 2019 CleanROM binder is single-device
# (only /dev/binder) so hwservicemanager/vndservicemanager can't open their
# nodes -> InitFatalReboot. Backported the AOSP multi-/dev-instance binder into
# drivers/staging/android/binder.c; this selects the three-device default.
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
#
# Unlock 3 - PowerVR DDK 1.9@4893595 KM (PORTING_LOG §55): gpu_rgx/ imported
# from the ALLDOCUBE X kernel (third_party/lineageos_kernel_cube_u1005) —
# matches the vendor UM blobs + rgx.fw.signed exactly. The gpu/Makefile
# dispatches obj-y += gpu_$(word 1,MTK_GPU_VERSION)/; word 2 (clyde) selects
# m1.9ED4893595 inside gpu_rgx/Makefile. Baseline defconfig has
# CONFIG_MTK_GPU_VERSION unset (falls back to mt8173/ = old DDK 1.7).
CONFIG_MTK_GPU_VERSION="rgx clyde 1.9ED"
# DDK 1.9 + display fences use the OLD staging sync framework (baseline
# already has CONFIG_SYNC/SW_SYNC/SW_SYNC_USER=y). MTK_SYNC pinned here —
# §54 lesson: verify it survives into the merged .config.
CONFIG_MTK_SYNC=y
#
# Diagnostic (§ALS, 2026-07-22) — expose /dev/i2c-* so userspace i2cdetect/i2cget
# (already shipped in /system/bin) can live-scan the sensor buses. Baseline has no
# i2c-dev nodes, so the LTR303-@0x29-absent question can't be answered from
# userspace. With this, scan every sensor bus: if 0x49 (or any unexplained addr)
# ACKs = neglected ALS at wrong addr/driver; if only known chips answer = LTR303
# is DNP/absent, close for good. Config-only, non-ABI, low boot risk. Remove once
# the ALS question is settled if the node exposure is unwanted long-term.
CONFIG_I2C_CHARDEV=y
