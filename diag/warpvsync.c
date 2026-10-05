/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * warpvsync: read-only measurement of the Warp GFX vertical refresh rate.
 *
 *   warpvsync [SECONDS]
 *
 * Polls the vertical-blank flag (bit 1 of 0x208, the bit csgfx.card's
 * GetVSyncState() reports) for SECONDS (default 3) and counts its rising
 * edges.  This shows whether the Warp timing generator is running at the
 * expected rate, independently of what the monitor accepts.
 */

#include <time.h>

#include "warpdiag.h"

static double
now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int
main(int argc, char **argv)
{
	struct warpdiag d;
	unsigned long samples = 0, high = 0, edges = 0;
	double t0, t, first = 0, last = 0, secs = 3.0;
	uint32_t v, prev;

	if (argc == 2) {
		secs = atof(argv[1]);
		if (secs < 0.1 || secs > 3600)
			errx(2, "SECONDS must be between 0.1 and 3600");
	} else if (argc != 1)
		errx(2, "usage: warpvsync [SECONDS]");

	warpdiag_open(&d, 0);
	prev = WARPDIAG_RD(&d, WARPDIAG_INT_STATUS) & WARPDIAG_VSYNC;
	t0 = now();
	do {
		v = WARPDIAG_RD(&d, WARPDIAG_INT_STATUS) & WARPDIAG_VSYNC;
		samples++;
		if (v)
			high++;
		if (v && !prev) {
			t = now();
			if (edges == 0)
				first = t;
			last = t;
			edges++;
		}
		prev = v;
	} while ((samples & 0xff) != 0 || now() - t0 < secs);

	printf("interval %.3f s, %lu samples, vblank flag high %.2f%%, "
	    "%lu rising edges\n", now() - t0, samples,
	    100.0 * high / samples, edges);
	if (edges > 1)
		printf("vertical rate %.3f Hz\n", (edges - 1) / (last - first));
	else
		printf("vertical rate unknown: the vertical-blank flag did not "
		    "toggle\n");
	warpdiag_close(&d);
	return edges > 1 ? 0 : 1;
}
