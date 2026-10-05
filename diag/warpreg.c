/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * warpreg: read or write one 32-bit Warp GFX display register.
 *
 *   warpreg OFFSET            read
 *   warpreg OFFSET VALUE      write VALUE, then read back
 *   warpreg -s OFFSET BITS    set BITS (read-modify-write), then read back
 *   warpreg -c OFFSET BITS    clear BITS (read-modify-write), then read back
 *
 * OFFSET must be 4-byte aligned and below 0x1000.  Writing needs root and
 * kern.securelevel <= 0.  Writes take effect immediately on the hardware;
 * see diag/README.md before using them.
 */

#include "warpdiag.h"

int
main(int argc, char **argv)
{
	struct warpdiag d;
	unsigned long off, val = 0;
	int op = 0;	/* 0 read, 1 write, 2 set bits, 3 clear bits */

	if (argc >= 2 && strcmp(argv[1], "-s") == 0) {
		op = 2;
		argv++;
		argc--;
	} else if (argc >= 2 && strcmp(argv[1], "-c") == 0) {
		op = 3;
		argv++;
		argc--;
	}
	if (argc < 2 || argc > 3 || (op >= 2 && argc != 3))
		errx(2, "usage: warpreg [-s | -c] OFFSET [VALUE]");

	off = warpdiag_number(argv[1]);
	if (off >= WARPDIAG_REG_WINDOW || (off & 3) != 0)
		errx(2, "OFFSET must be 4-byte aligned and below 0x%lx",
		    WARPDIAG_REG_WINDOW);
	if (argc == 3) {
		val = warpdiag_number(argv[2]);
		if (val > 0xffffffffUL)
			errx(2, "VALUE does not fit in 32 bits");
		if (op == 0)
			op = 1;
	}

	warpdiag_open(&d, op != 0);
	switch (op) {
	case 1:
		WARPDIAG_WR(&d, off, val);
		break;
	case 2:
		WARPDIAG_WR(&d, off, WARPDIAG_RD(&d, off) | (uint32_t)val);
		break;
	case 3:
		WARPDIAG_WR(&d, off, WARPDIAG_RD(&d, off) & ~(uint32_t)val);
		break;
	}
	printf("%03lx=%08x\n", off, (unsigned)WARPDIAG_RD(&d, off));
	warpdiag_close(&d);
	return 0;
}
