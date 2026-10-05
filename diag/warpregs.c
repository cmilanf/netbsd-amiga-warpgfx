/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * warpregs: read-only dump of the Warp GFX display registers, followed by a
 * decoded summary of the programmed mode.
 *
 *   warpregs [-r]
 *
 * -r prints only the raw register dump.
 */

#include "warpdiag.h"

static const unsigned offsets[] = {
	0x000, 0x004, 0x008, 0x00c, 0x010, 0x014, 0x018, 0x01c,
	0x020, 0x024, 0x028, 0x02c, 0x030,
	0x100, 0x104, 0x108, 0x10c, 0x110, 0x114, 0x118, 0x11c,
	0x120, 0x124, 0x128, 0x12c, 0x130, 0x134,
	0x200, 0x204, 0x208, 0x20c,
};

static void
decode(struct warpdiag *d)
{
	uint32_t pitch, mode, total, clk, status, scale;
	unsigned width, height, htotal, vtotal, sel, pitch16;
	unsigned long hz;

	pitch = WARPDIAG_RD(d, WARPDIAG_FORMAT_PITCH);
	mode = WARPDIAG_RD(d, WARPDIAG_MODE);
	total = WARPDIAG_RD(d, WARPDIAG_HV_TOTAL);
	clk = WARPDIAG_RD(d, WARPDIAG_CLOCK_CONTROL);
	status = WARPDIAG_RD(d, WARPDIAG_CLOCK_STATUS);
	scale = WARPDIAG_RD(d, WARPDIAG_SCALE);

	width = WARPDIAG_RD(d, WARPDIAG_H_ACTIVE) & 0xfff;
	height = WARPDIAG_RD(d, WARPDIAG_V_ACTIVE) & 0xfff;
	htotal = total & 0xfff;
	vtotal = (total >> 12) & 0xfff;
	sel = clk & 7;
	pitch16 = pitch >> 22;

	printf("\noutput:   %s, %s pixels, sync %ch %cv%s\n",
	    (mode & 0x80) ? "Warp framebuffer" : "native Amiga video",
	    (mode & 0x10) ? "32-bit" : (mode & 0x08) ? "16-bit" : "8-bit",
	    (mode & 0x02) ? '-' : '+', (mode & 0x01) ? '-' : '+',
	    (scale & 0x3c) ? ", scaled" : "");
	printf("timing:   %ux%u active, %ux%u total\n", width, height,
	    htotal, vtotal);
	printf("memory:   pitch %u bytes, %u lines, offset 0x%08x\n",
	    pitch16 * 16, (unsigned)((pitch >> 10) & 0xfff),
	    (unsigned)(WARPDIAG_RD(d, WARPDIAG_FB_OFFSET) * 16));
	if (sel < 6) {
		hz = warpdiag_clock_hz[sel];
		printf("clock:    index %u = %lu.%03lu MHz (csgfx.card 22.96 "
		    "table), %s\n", sel, hz / 1000000, (hz / 1000) % 1000,
		    (status & WARPDIAG_CLOCK_READY) ? "ready" : "NOT ready");
		if (htotal != 0 && vtotal != 0)
			printf("refresh:  %.2f Hz expected (measure with "
			    "warpvsync)\n",
			    (double)hz / ((double)htotal * vtotal));
	} else {
		printf("clock:    index %u (unknown), %s\n", sel,
		    (status & WARPDIAG_CLOCK_READY) ? "ready" : "NOT ready");
	}
	printf("sprite:   %s\n", (scale & 1) ? "enabled" : "disabled");
	printf("blitter:  %s\n",
	    (WARPDIAG_RD(d, WARPDIAG_BLT_STATUS) & 0x19) ? "busy" : "idle");
}

int
main(int argc, char **argv)
{
	struct warpdiag d;
	size_t i;
	int raw = 0;

	if (argc == 2 && strcmp(argv[1], "-r") == 0)
		raw = 1;
	else if (argc != 1)
		errx(2, "usage: warpregs [-r]");

	warpdiag_open(&d, 0);
	printf("control registers at physical 0x%08lx\n", d.reg_pa);
	for (i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++)
		printf("%03x=%08x%s", offsets[i],
		    (unsigned)WARPDIAG_RD(&d, offsets[i]),
		    (i % 4) == 3 ? "\n" : "  ");
	printf("\n");
	if (!raw)
		decode(&d);
	warpdiag_close(&d);
	return 0;
}
