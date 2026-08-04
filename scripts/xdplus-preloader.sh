#!/bin/bash
# xdplus-preloader.sh — flash and rescue a GPD XD+ over the MediaTek preloader,
# with no SP Flash Tool, no Wine and no Windows drivers.
#
# This is the path that works when nothing else does: it talks to the MT8176 boot
# ROM, which answers on every power-up whether or not Android, TWRP, fastboot or
# a display are alive. It is how you install onto a stock device, and how you get
# a dead one back.
#
#   ./xdplus-preloader.sh identify              what is this device? (read-only)
#   ./xdplus-preloader.sh backup <dir>          save the irreplaceable partitions
#   ./xdplus-preloader.sh restore <dir> <part>  write one partition back
#   ./xdplus-preloader.sh install <dir>         write boot/recovery/system/vendor
#
# Options:
#   --board-check    also read `lk` and identify the board revision (identify)
#   --yes            skip confirmation prompts
#   --repartition    install onto a STOCK layout, rewriting the partition table
#                    from the SP Flash Tool package's `MBR` blob.
#                    ⚠️ DESTROYS ALL DATA AND IS UNVERIFIED — read the warning below.
#   --mbr <file>     where that blob is, if not <dir>/MBR
#
# ── HOW THIS DEVICE DIFFERS FROM EVERY OTHER ANDROID DEVICE ───────────────────
#
# The bootloader is LOCKED and this ROM assumes it stays locked. `fastboot flash`
# is refused. Partitions are written either from inside TWRP, or from here.
#
# ⚠️ THIS SCRIPT NEVER TOUCHES `preloader`, `seccfg` OR THE BOOTLOADER LOCK.
# `boot`, `recovery`, `system` and `vendor` are all recoverable — if you write a
# bad one you come back here and write a good one. The preloader and seccfg are
# NOT recoverable: getting those wrong ends the device. There is deliberately no
# code path here that writes them, and you should not add one.
#
# ── THE SESSION ALWAYS ENDS WITH THE DEVICE PARKED, AND IT LOOKS DEAD ─────────
#
# ⚠️ When a preloader session finishes — successfully or not — the device is left
# in Download Agent mode: red LED, no adb, no fastboot, and THE POWER BUTTON
# APPEARS NOT TO WORK. It is not bricked and nothing has been written that you
# did not ask for. The DA runs from RAM and the USB cable is what keeps it there:
# with power present, the PMIC re-powers straight back into the preloader, which
# is exactly what makes the button feel dead.
#
#   → UNPLUG THE USB CABLE FIRST, then hold power for ~10 seconds.
#
# `mtk reset` does NOT rescue this; it refuses to act on an attached session and
# tells you to pull the cable. If you want to know whether the device really
# re-enumerated, watch the Bus/Device numbers in `lsusb` — an unchanged number
# means nothing happened.
set -uo pipefail

die()  { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
warn() { echo "⚠️  $*" >&2; }

# ── locating mtkclient ────────────────────────────────────────────────────────
# Point XDPL_MTKDIR at a mtkclient checkout, or keep one beside this script.
MTKDIR="${XDPL_MTKDIR:-}"
if [ -z "$MTKDIR" ]; then
	for c in "$(dirname "$0")/mtkclient" "$(dirname "$0")/../mtkclient" "$HOME/mtkclient"; do
		[ -f "$c/mtk.py" ] && MTKDIR="$c" && break
	done
fi
[ -n "$MTKDIR" ] && [ -f "$MTKDIR/mtk.py" ] || die "mtkclient not found.
Get it with:
    git clone https://github.com/bkerler/mtkclient
    cd mtkclient && python -m venv .venv && .venv/bin/pip install -r requirements.txt
then re-run with XDPL_MTKDIR=/path/to/mtkclient"

PY="$MTKDIR/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"
[ -x "$PY" ] || die "no python3 found"

# ⚠️ mtkclient writes its session state to a FILE named ./.state in the working
# directory. Run it somewhere disposable: a directory that already contains a
# .state DIRECTORY kills the run with IsADirectoryError *after* the Download
# Agent has been uploaded — i.e. it parks the device and you have to power-cycle.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

mtk() { ( cd "$WORK" && "$PY" "$MTKDIR/mtk.py" "$@" ); }

# Open the preloader window without touching the device. The window appears on
# every power-up, so a warm `adb reboot` is enough — the cable never has to move.
# mtkclient must already be listening, hence the delay.
arm_warm_reboot() {
	command -v adb >/dev/null || return 0
	adb devices 2>/dev/null | grep -q '	device$' || {
		echo "    (device not on adb — power it on yourself once the tool is waiting)"
		return 0
	}
	( sleep 5; adb reboot >/dev/null 2>&1 ) &
	echo "    (warm reboot armed: the device will reboot in 5s to open the window)"
}

park_notice() {
	echo
	echo "──────────────────────────────────────────────────────────────────────"
	echo " The device is now parked in preloader mode. This is normal."
	echo " UNPLUG THE USB CABLE, then hold power ~10s. It will boot after that."
	echo "──────────────────────────────────────────────────────────────────────"
}

confirm() {
	[ "${ASSUME_YES:-0}" = "1" ] && return 0
	printf '%s [type YES to continue] ' "$1"
	read -r a; [ "$a" = "YES" ] || die "aborted"
}

# ── device identity ───────────────────────────────────────────────────────────
# The original GPD XD is a Rockchip RK3288 and cannot speak this protocol at all,
# so simply connecting rules it out. The positive check is the SoC id, which the
# preloader reports itself.
EXPECT_HWCODE="0x8176"

# md5 of the first 331008 bytes of the `lk` partition on a NEW-BOARD ("VR") XD+,
# i.e. GPD's own lk.bin from GPD_EN_VR-images-v1.14. The rest of the partition is
# padding. GPD's published test for board revision is to read the build number in
# Android and look for "VR" — useless here, since this tool exists precisely for
# devices that cannot boot. Hashing `lk` answers the same question offline.
VR_LK_MD5="59e09dc5b5ef06f403285b96b17e9d0b"
VR_LK_LEN=331008

# Partitions that are UNIQUE TO YOUR UNIT and exist nowhere else in the world:
# Wi-Fi/Bluetooth MAC addresses, radio and sensor calibration, DRM keys. If you
# lose these, no download recovers them. They are tiny; always back them up.
PRECIOUS="proinfo nvram nvdata protect1 protect2"
# Partitions this script is willing to write. Deliberately short.
WRITABLE="boot recovery system vendor"

parse_gpt() {   # stdin: mtk printgpt output → "name offset length" lines
	tr -d '\r' | sed -n 's/^\([a-z_0-9]\+\): *Offset \(0x[0-9a-f]*\), Length \(0x[0-9a-f]*\).*/\1 \2 \3/p'
}

classify_layout() {   # stdin: parsed gpt → prints XDPLUS | STOCK | UNKNOWN
	local t; t=$(cat)
	local boot recovery vendor
	boot=$(echo "$t"     | awk '$1=="boot"{print strtonum($3)}')
	recovery=$(echo "$t" | awk '$1=="recovery"{print strtonum($3)}')
	vendor=$(echo "$t"   | awk '$1=="vendor"{print strtonum($3)}')
	if [ -n "$vendor" ] && [ "${boot:-0}" -ge 67108864 ] && [ "${recovery:-0}" -ge 100663296 ]; then
		echo XDPLUS
	elif [ -z "$vendor" ] && [ "${boot:-0}" = "16777216" ]; then
		echo STOCK
	else
		echo UNKNOWN
	fi
}

cmd_identify() {
	step "Reading the partition table (nothing is written)"
	arm_warm_reboot
	local log="$WORK/gpt.log"
	mtk printgpt >"$log" 2>&1 || die "could not talk to the device. See $WORK/gpt.log"

	local hw; hw=$(tr -d '\r' <"$log" | sed -n 's/.*HW code:[[:space:]]*\(0x[0-9a-f]*\).*/\1/p' | head -1)
	echo "SoC HW code : ${hw:-unknown}"
	[ "$hw" = "$EXPECT_HWCODE" ] || {
		warn "This is NOT an MT8176. Expected $EXPECT_HWCODE."
		warn "If you are holding an original GPD XD (Rockchip), this ROM is not for it."
		die "refusing to go further on unknown hardware"
	}

	local gpt; gpt=$(parse_gpt <"$log")
	[ -n "$gpt" ] || die "no partition table came back. See $WORK/gpt.log"
	local layout; layout=$(echo "$gpt" | classify_layout)
	echo "Partitions  : $(echo "$gpt" | wc -l)"
	echo "Layout      : $layout"
	case "$layout" in
		XDPLUS) echo "              → already repartitioned for this ROM. install works." ;;
		STOCK)  echo "              → stock GPD layout: no vendor partition, boot/recovery too small."
		        echo "                install needs --repartition. Read the warning first." ;;
		*)      warn "unrecognised layout — this script will refuse to write to it." ;;
	esac
	echo "$gpt" > "${XDPL_GPT_OUT:-/dev/null}" 2>/dev/null || true

	if [ "${BOARD_CHECK:-0}" = "1" ]; then
		echo
		warn "The board check needs a SECOND preloader session, so the device"
		warn "must be power-cycled between them (unplug, hold power, boot)."
		printf 'Ready for the second session? [type YES] '
		read -r a; [ "$a" = "YES" ] || { park_notice; return 0; }
		step "Reading lk to identify the board revision"
		arm_warm_reboot
		mtk r lk "$WORK/lk.img" >"$WORK/lk.log" 2>&1 || die "could not read lk. See $WORK/lk.log"
		local got; got=$(head -c "$VR_LK_LEN" "$WORK/lk.img" | md5sum | cut -d' ' -f1)
		if [ "$got" = "$VR_LK_MD5" ]; then
			echo "Board       : NEW ('VR'), matching GPD's own lk.bin exactly"
		else
			echo "Board       : NOT the new-board lk we know ($got)"
			strings -a "$WORK/lk.img" 2>/dev/null | grep -q WISKY8176_TB_N \
				&& echo "              (but it does carry the WISKY8176_TB_N board string)" \
				|| warn "and no WISKY8176_TB_N string either — treat as unknown hardware"
		fi
	fi
	park_notice
}

cmd_backup() {
	local dir="${1:?usage: backup <directory>}"
	mkdir -p "$dir" || die "cannot create $dir"
	step "Backing up the partitions that exist nowhere else"
	echo "    $PRECIOUS"
	echo "    plus boot and recovery, so you can always get back to today's state."
	echo "    Everything is read; nothing is written."
	arm_warm_reboot
	local parts="$PRECIOUS boot recovery"
	local names files
	names=$(echo $parts | tr ' ' ',')
	files=$(for p in $parts; do printf '%s,' "$dir/$p.img"; done | sed 's/,$//')
	mtk r "$names" "$files" 2>&1 | tr '\r' '\n' | grep -aiE "Dumping|Error|Couldn't" || true
	echo
	local ok=1
	for p in $parts; do
		if [ -s "$dir/$p.img" ]; then
			echo "  $(md5sum "$dir/$p.img")"
		else
			warn "MISSING: $p"; ok=0
		fi
	done
	( cd "$dir" && md5sum ./*.img > md5sums.txt 2>/dev/null ) || true
	[ "$ok" = "1" ] && echo "Backup complete: $dir" || warn "Backup INCOMPLETE — do not rely on it."
	park_notice
}

cmd_restore() {
	local dir="${1:?usage: restore <directory> <partition>}"
	local part="${2:?usage: restore <directory> <partition>}"
	local img="$dir/$part.img"
	[ -f "$img" ] || die "no such backup: $img"
	case " $WRITABLE $PRECIOUS " in
		*" $part "*) ;;
		*) die "refusing to write '$part' — this script only writes: $WRITABLE $PRECIOUS" ;;
	esac
	confirm "Write $img ($(stat -c%s "$img") bytes) to partition '$part'?"
	step "Writing $part"
	arm_warm_reboot
	mtk w "$part" "$img" 2>&1 | tr '\r' '\n' | grep -aiE "Writing|Error|Couldn't|Done" || true
	park_notice
}

cmd_install() {
	local dir="${1:?usage: install <directory with boot.img/recovery.img/system.img/vendor.img>}"
	step "Checking what you are about to install"
	local have=""
	for p in $WRITABLE; do [ -f "$dir/$p.img" ] && have="$have $p"; done
	[ -n "$have" ] || die "found none of boot.img/recovery.img/system.img/vendor.img in $dir"
	for p in $have; do echo "  $p.img  $(stat -c%s "$dir/$p.img") bytes"; done
	[ -f "$dir/boot.img" ] && { head -c 8 "$dir/boot.img" | grep -q 'ANDROID!' \
		|| die "boot.img has no ANDROID! magic — refusing"; }

	if [ "${REPARTITION:-0}" = "1" ]; then
		local mbr="${MBR_FILE:-$dir/MBR}"
		[ -f "$mbr" ] || die "--repartition needs the partition-table blob.
It is the file named 'MBR' inside the SP Flash Tool package for this ROM (17408
bytes). Put it in $dir, or pass --mbr <file>."
		# Sanity-check the blob before letting it near the device: it must be a
		# real GPT, and it must describe THIS ROM's layout rather than the stock
		# one. Writing a table that does not match the images is how you produce
		# a device that flashes cleanly and then boots to nothing.
		dd if="$mbr" bs=1 skip=512 count=8 status=none | grep -q 'EFI PART' \
			|| die "$mbr is not a GPT image (no 'EFI PART' signature at offset 512)"
		echo
		warn "──────────────────────────────────────────────────────────────────"
		warn " --repartition REWRITES THE PARTITION TABLE."
		warn " Every partition is redefined and everything on the device is lost,"
		warn " including the per-unit calibration in nvram/nvdata/proinfo and the"
		warn " protect partitions, which NO DOWNLOAD CAN REPLACE."
		warn ""
		warn " ⚠️ THIS PATH HAS NOT BEEN VERIFIED END TO END."
		warn " It writes the table to the start of the user area, which covers"
		warn " 'pgpt' only. It does NOT touch the preloader, which lives in the"
		warn " eMMC boot area — so a bad table is recoverable from here."
		warn ""
		warn " Run 'backup' FIRST and check the md5sums came out. Seriously."
		warn "──────────────────────────────────────────────────────────────────"
		confirm "Rewrite the partition table from $mbr and destroy all data?"
		step "Writing the partition table"
		arm_warm_reboot
		# Offset 0 of the user area = the 'pgpt' partition in MediaTek's scatter
		# (0x0, length 0x80000). Writing here replaces MBR + primary GPT.
		mtk wo 0x0 "$mbr" 2>&1 | tr '\r' '\n' | grep -aiE "Writing|Error|Couldn't|Done" || true
		echo
		warn "Table written. The device must be POWER-CYCLED before the new layout"
		warn "is visible — unplug, hold power, then run 'identify' to confirm it"
		warn "reports XDPLUS, and only then run 'install' again without --repartition."
		park_notice
		return 0
	fi

	confirm "Write$have to the device?"
	step "Writing"
	arm_warm_reboot
	local names files
	names=$(echo $have | tr ' ' ',' | sed 's/^,//')
	files=$(for p in $have; do printf '%s,' "$dir/$p.img"; done | sed 's/,$//')
	mtk w "$names" "$files" 2>&1 | tr '\r' '\n' | grep -aiE "Writing|Error|Couldn't|Done" || true
	echo
	echo "Written. Verify with:  $0 backup /tmp/verify   and compare md5sums."
	park_notice
}

ASSUME_YES=0; BOARD_CHECK=0; REPARTITION=0; MBR_FILE=""
ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
		--yes|-y)      ASSUME_YES=1; shift;;
		--board-check) BOARD_CHECK=1; shift;;
		--repartition) REPARTITION=1; shift;;
		--mbr)         MBR_FILE="$2"; shift 2;;
		-h|--help)     sed -n '2,60p' "$0"; exit 0;;
		-*)            die "unknown option: $1";;
		*)             ARGS+=("$1"); shift;;
	esac
done
set -- "${ARGS[@]:-}"

case "${1:-}" in
	identify) cmd_identify ;;
	backup)   shift; cmd_backup "$@" ;;
	restore)  shift; cmd_restore "$@" ;;
	install)  shift; cmd_install "$@" ;;
	*)        sed -n '2,60p' "$0"; exit 1 ;;
esac
