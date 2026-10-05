/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * warpclkmon: read-only monitor of the Warp GFX pixel-clock status.
 *
 *   warpclkmon [SECONDS]
 *
 * Samples the clock status register (0x200) continuously for SECONDS
 * (default 10) and reports how often the ready bit (bit 1) read clear and
 * every distinct value seen.  A clock that loses lock shows up here.
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
	unsigned long samples = 0, notready = 0, changes = 0;
	double t0, secs = 10.0;
	uint32_t v, prev, seen[8];
	int nseen = 0, i;

	if (argc == 2) {
		secs = atof(argv[1]);
		if (secs < 0.1 || secs > 3600)
			errx(2, "SECONDS must be between 0.1 and 3600");
	} else if (argc != 1)
		errx(2, "usage: warpclkmon [SECONDS]");

	warpdiag_open(&d, 0);
	prev = WARPDIAG_RD(&d, WARPDIAG_CLOCK_STATUS);
	t0 = now();
	do {
		v = WARPDIAG_RD(&d, WARPDIAG_CLOCK_STATUS);
		samples++;
		if ((v & WARPDIAG_CLOCK_READY) == 0)
			notready++;
		if (v != prev)
			changes++;
		for (i = 0; i < nseen && seen[i] != v; i++)
			continue;
		if (i == nseen && nseen < 8)
			seen[nseen++] = v;
		prev = v;
	} while ((samples & 0xff) != 0 || now() - t0 < secs);

	printf("%.1f s, %lu samples, ready bit clear %lu times, "
	    "%lu value changes\nvalues seen:", now() - t0, samples, notready,
	    changes);
	for (i = 0; i < nseen; i++)
		printf(" %08x", (unsigned)seen[i]);
	printf("\nclock control 204=%08x, mode 11c=%08x\n",
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_CLOCK_CONTROL),
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_MODE));
	warpdiag_close(&d);
	return notready == 0 ? 0 : 1;
}
