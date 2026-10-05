# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
#
# Shared functions for the WarpGFX test scripts; sourced, not executed.
# Expects DIAG to name the directory holding the diagnostic binaries.

log() {
	echo "$(date '+%H:%M:%S') $*"
}

die() {
	echo "error: $*" >&2
	exit 1
}

# Refuse to run unless register writes can work.
check_access() {
	[ "$(id -u)" -eq 0 ] || die "run as root"
	level=$(/sbin/sysctl -n kern.securelevel 2>/dev/null || echo 1)
	[ "$level" -le 0 ] || die "kern.securelevel is $level; register writes need <= 0 (see README.md)"
	for tool in warpmode warpvsync warpredraw; do
		[ -x "$DIAG/$tool" ] || die "missing $DIAG/$tool"
	done
}

# Print the warpmode name of the mode the kernel driver set at boot.
kernel_mode() {
	{
		[ -r /var/run/dmesg.boot ] && cat /var/run/dmesg.boot
		/sbin/dmesg 2>/dev/null
	} | sed -n 's/^.*warpgfx[0-9]*: \([0-9]*x[0-9]*\)p[0-9]*, 16 bpp.*$/\1/p' |
	tail -n 1 | {
		read -r geometry || geometry=
		case $geometry in
		640x480) echo 480 ;;
		800x600) echo 600 ;;
		1280x720) echo 720 ;;
		1024x768) echo 768 ;;
		1280x1024) echo 1024 ;;
		1920x1080) echo 1080 ;;
		*) echo "" ;;
		esac
	}
}

# Put the display back the way the kernel console expects it.
restore_console() {
	trap - EXIT INT TERM HUP
	if [ -n "${RESTORE_MODE:-}" ]; then
		log "restoring kernel mode $RESTORE_MODE and redrawing the console"
		"$DIAG/warpmode" "$RESTORE_MODE" 0x0000 || true
		"$DIAG/warpredraw" || true
	fi
}

# step SECONDS LABEL WARPMODE-ARGUMENTS...
step() {
	hold=$1
	label=$2
	shift 2
	log "$label"
	"$DIAG/warpmode" "$@" || die "warpmode $* failed"
	sleep 2
	"$DIAG/warpvsync" 2 | sed -n 's/^vertical rate/    measured vertical rate/p'
	[ "$hold" -gt 5 ] && sleep $((hold - 5))
	return 0
}

setup_restore() {
	RESTORE_MODE=${RESTORE_MODE:-$(kernel_mode)}
	[ -n "$RESTORE_MODE" ] || die "cannot tell the kernel mode from dmesg; set RESTORE_MODE"
	trap 'restore_console' EXIT
	trap 'exit 130' INT TERM HUP
}
