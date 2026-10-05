#!/bin/sh
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
#
# Cycle the Warp output through every console mode, each held HOLD seconds
# (default 30) and filled with its own colour, so you can note on the
# monitor which modes it accepts.  Repeats CYCLES times (default 1), then
# restores the kernel's mode and redraws the console, also on Ctrl-C.
#
#   HOLD=30 CYCLES=2 ./warptest-modes.sh | tee /tmp/warptest-modes.log
#
# Needs root and kern.securelevel <= 0.  See README.md.
set -eu

DIAG=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIAG/warptest-common.sh"

HOLD=${HOLD:-30}
CYCLES=${CYCLES:-1}
case $HOLD$CYCLES in *[!0-9]*) die "HOLD and CYCLES must be integers" ;; esac

check_access
setup_restore
log "kernel mode is $RESTORE_MODE; $CYCLES cycle(s) of 7 steps, ${HOLD}s each"

c=1
while [ "$c" -le "$CYCLES" ]; do
	step "$HOLD" "cycle $c: native Amiga video, 1280x1024 108 MHz (Amiga picture)" native
	step "$HOLD" "cycle $c: RED     1280x1024 60 Hz, 108 MHz" 1024 0xf800
	step "$HOLD" "cycle $c: GREEN   1280x720 60 Hz, 74.25 MHz" 720 0x07e0
	step "$HOLD" "cycle $c: BLUE    1024x768 60 Hz, 65 MHz" 768 0x001f
	step "$HOLD" "cycle $c: YELLOW  800x600 60 Hz, 40 MHz" 600 0xffe0
	step "$HOLD" "cycle $c: WHITE   640x480 60 Hz, 25.175 MHz" 480 0xffff
	step "$HOLD" "cycle $c: MAGENTA 1920x1080 60 Hz, 148.5 MHz" 1080 0xf81f
	c=$((c + 1))
done
log "done"
