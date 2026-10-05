#!/bin/sh
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
#
# Isolate a 1920x1080 output problem: compare 1080p at 30, 50, and 60 Hz,
# on the 74.25 MHz and 148.5 MHz pixel clocks, with both register orders,
# against a known-good 1280x720 baseline.  Each step is held HOLD seconds
# (default 60) with its own colour, then the kernel's mode is restored.
#
#   ./warptest-1080.sh | tee /tmp/warptest-1080.log
#
# On Warp firmware 2296 every 74.25 MHz step holds and every 148.5 MHz step
# drops within a second, which locates the fault in the 148.5 MHz output.
# Needs root and kern.securelevel <= 0.  See README.md.
set -eu

DIAG=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$DIAG/warptest-common.sh"

HOLD=${HOLD:-60}
case $HOLD in ''|*[!0-9]*) die "HOLD must be an integer" ;; esac

check_access
setup_restore
log "kernel mode is $RESTORE_MODE; 5 steps, ${HOLD}s each after a 20s baseline"

step 20      "GREEN   1280x720 60 Hz, 74.25 MHz (baseline)" 720 0x07e0
step "$HOLD" "CYAN    1920x1080 30 Hz, 74.25 MHz" 1080p30 0x07ff
step "$HOLD" "WHITE   1920x1080 60 Hz, 148.5 MHz, csgfx.card 22.96 order" -o 1080 0xffff
step "$HOLD" "ORANGE  1920x1080 50 Hz, 148.5 MHz" 1080p50 0xfc00
step "$HOLD" "MAGENTA 1920x1080 60 Hz, 148.5 MHz, kernel driver order" 1080 0xf81f
log "done"
