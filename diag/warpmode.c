/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * warpmode: program a Warp GFX display mode from user space.
 *
 *   warpmode -l
 *   warpmode [-o] MODE [COLOR16]
 *
 * The register values and their order are those of the WarpGFX kernel
 * driver (pixel clock first, then the mode registers and the commit
 * pulse).  -o uses the csgfx.card 22.96 order instead: SetGC() programs the
 * mode and pulses the commit bit, then SetClock() changes the clock and
 * pulses it again.  COLOR16 fills the visible area of a 16-bit mode with
 * one R5G6B5 colour so a monitor can show which mode is active.
 *
 * The kernel console keeps drawing for its own mode, so the screen content
 * is not meaningful after a change.  Restore the kernel's mode with
 * warpmode and redraw the console with warpredraw.  Needs root and
 * kern.securelevel <= 0.
 */

#include "warpdiag.h"

struct mode {
	const char *name;
	const char *descr;
	uint32_t clock;
	uint32_t pitch;
	uint32_t timing[7];	/* 0x100 to 0x118 */
	uint32_t commit;	/* 0x11c without the commit pulse */
};

static const struct mode modes[] = {
	{ "native", "native Amiga video scaled to 1280x1024 (SetSwitch(FALSE))",
	  4, 0x50100140,
	  { 0x500, 0x500698, 0x5305a0, 0x400, 0x40042a, 0x401404, 0x42a698 },
	  0x10 },
	{ "480", "640x480 60 Hz, 16-bit, 25.175 MHz, -h -v",
	  0, 0x14078050,
	  { 0x280, 0x280320, 0x2902f0, 0x1e0, 0x1e020d, 0x1ea1ec, 0x20d320 },
	  0x8b },
	{ "600", "800x600 60 Hz, 16-bit, 40 MHz",
	  1, 0x19096064,
	  { 0x320, 0x320420, 0x3483c8, 0x258, 0x258274, 0x25925d, 0x274420 },
	  0x88 },
	{ "720", "1280x720 60 Hz, 16-bit, 74.25 MHz",
	  3, 0x280b40a0,
	  { 0x500, 0x500672, 0x56e596, 0x2d0, 0x2d02ee, 0x2d52da, 0x2ee672 },
	  0x88 },
	{ "768", "1024x768 60 Hz, 16-bit, 65 MHz, -h -v",
	  2, 0x200c0080,
	  { 0x400, 0x400540, 0x4184a0, 0x300, 0x300326, 0x303309, 0x326540 },
	  0x8b },
	{ "1024", "1280x1024 60 Hz, 16-bit, 108 MHz",
	  4, 0x281000a0,
	  { 0x500, 0x500698, 0x5305a0, 0x400, 0x40042a, 0x401404, 0x42a698 },
	  0x88 },
	{ "1080", "1920x1080 60 Hz, 16-bit, 148.5 MHz",
	  5, 0x3c10e0f0,
	  { 0x780, 0x780898, 0x7d8804, 0x438, 0x438465, 0x43c441, 0x465898 },
	  0x88 },
	{ "1080p30", "1920x1080 30 Hz, 16-bit, 74.25 MHz (1080p60 timing)",
	  3, 0x3c10e0f0,
	  { 0x780, 0x780898, 0x7d8804, 0x438, 0x438465, 0x43c441, 0x465898 },
	  0x88 },
	{ "1080p50", "1920x1080 50 Hz, 16-bit, 148.5 MHz (2640 total)",
	  5, 0x3c10e0f0,
	  { 0x780, 0x780a50, 0x9909bc, 0x438, 0x438465, 0x43c441, 0x465a50 },
	  0x88 },
};

static void
set_clock(struct warpdiag *d, uint32_t clock)
{
	size_t i;

	WARPDIAG_WR(d, WARPDIAG_CLOCK_CONTROL, 0x10 | clock);
	/* As the 1.1 driver: let a stale ready bit drop (at most ~10 ms). */
	for (i = 0; i < 1000 &&
	    (WARPDIAG_RD(d, WARPDIAG_CLOCK_STATUS) & WARPDIAG_CLOCK_READY); i++)
		usleep(10);
	for (i = 0; i < 1000000 &&
	    !(WARPDIAG_RD(d, WARPDIAG_CLOCK_STATUS) & WARPDIAG_CLOCK_READY);
	    i++)
		continue;
	if (!(WARPDIAG_RD(d, WARPDIAG_CLOCK_STATUS) & WARPDIAG_CLOCK_READY))
		warnx("pixel clock %u did not report ready", (unsigned)clock);
}

static void
set_mode(struct warpdiag *d, const struct mode *m)
{
	size_t i;

	/* Unscaled output, hardware sprite off. */
	WARPDIAG_WR(d, WARPDIAG_SCALE, WARPDIAG_RD(d, WARPDIAG_SCALE) & ~0x3dU);
	WARPDIAG_WR(d, WARPDIAG_OUTPUT_AUX, 0);
	WARPDIAG_WR(d, WARPDIAG_FB_OFFSET, 0);
	WARPDIAG_WR(d, WARPDIAG_FORMAT_PITCH, m->pitch);
	for (i = 0; i < 7; i++)
		WARPDIAG_WR(d, WARPDIAG_H_ACTIVE + 4 * i, m->timing[i]);
	WARPDIAG_WR(d, WARPDIAG_MODE, m->commit | 4);
	WARPDIAG_WR(d, WARPDIAG_MODE, m->commit);
}

static void
fill(struct warpdiag *d, const struct mode *m, uint32_t color)
{
	volatile uint32_t *fb;
	size_t len, i;
	uint32_t word;

	len = (size_t)(m->pitch >> 22) * 16 * ((m->pitch >> 10) & 0xfff);
	fb = warpdiag_map_fb(d, len);
	word = (color << 16) | color;
	for (i = 0; i < len / 4; i++)
		fb[i] = word;
	munmap((void *)(uintptr_t)fb, len);
}

int
main(int argc, char **argv)
{
	const struct mode *m = NULL;
	struct warpdiag d;
	unsigned long color = 0;
	size_t i;
	int order2296 = 0, dofill = 0;

	if (argc == 2 && strcmp(argv[1], "-l") == 0) {
		for (i = 0; i < sizeof(modes) / sizeof(modes[0]); i++)
			printf("%-8s %s\n", modes[i].name, modes[i].descr);
		return 0;
	}
	if (argc > 1 && strcmp(argv[1], "-o") == 0) {
		order2296 = 1;
		argv++;
		argc--;
	}
	if (argc < 2 || argc > 3)
		errx(2, "usage: warpmode -l | warpmode [-o] MODE [COLOR16]");
	for (i = 0; i < sizeof(modes) / sizeof(modes[0]); i++)
		if (strcmp(argv[1], modes[i].name) == 0)
			m = &modes[i];
	if (m == NULL)
		errx(2, "unknown mode '%s' (warpmode -l lists modes)", argv[1]);
	if (argc == 3) {
		color = warpdiag_number(argv[2]);
		if (color > 0xffff)
			errx(2, "COLOR16 must be a 16-bit R5G6B5 value");
		if ((m->commit & 0x80) == 0)
			errx(2, "mode '%s' shows native video; no fill", m->name);
		dofill = 1;
	}

	warpdiag_open(&d, 1);
	if (dofill)
		fill(&d, m, (uint32_t)color);

	if (order2296) {
		set_mode(&d, m);
		if ((WARPDIAG_RD(&d, WARPDIAG_CLOCK_CONTROL) & 7) != m->clock) {
			set_clock(&d, m->clock);
			WARPDIAG_WR(&d, WARPDIAG_MODE,
			    WARPDIAG_RD(&d, WARPDIAG_MODE) | 4);
			WARPDIAG_WR(&d, WARPDIAG_MODE,
			    WARPDIAG_RD(&d, WARPDIAG_MODE) & ~4U);
		}
	} else {
		if ((WARPDIAG_RD(&d, WARPDIAG_CLOCK_CONTROL) & 7) != m->clock ||
		    !(WARPDIAG_RD(&d, WARPDIAG_CLOCK_STATUS) &
		    WARPDIAG_CLOCK_READY))
			set_clock(&d, m->clock);
		set_mode(&d, m);
	}

	printf("%s: 004=%08x 11c=%08x 200=%08x 204=%08x 128=%08x\n", m->name,
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_FORMAT_PITCH),
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_MODE),
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_CLOCK_STATUS),
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_CLOCK_CONTROL),
	    (unsigned)WARPDIAG_RD(&d, WARPDIAG_SCALE));
	warpdiag_close(&d);
	return 0;
}
