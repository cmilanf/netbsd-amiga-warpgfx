/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * Shared helpers for the WarpGFX diagnostic tools.
 *
 * The tools access the CS-Lab Warp GFX through /dev/mem.  The physical
 * addresses are taken from the kernel's Zorro attach messages
 * ("man/pro 5120/100" framebuffer, "man/pro 5120/101" control registers),
 * so they follow whatever AutoConfig assigned on the running machine.  The
 * WARPGFX_FB_PA and WARPGFX_REG_PA environment variables override them.
 *
 * Only the 4 KiB display block of the control aperture is ever mapped.
 * The Warp communication mailbox at offset 0x1000 and above, used by
 * AmigaOS cswarp.library, is deliberately out of reach.
 */

#ifndef WARPDIAG_H
#define WARPDIAG_H

#include <sys/types.h>
#include <sys/mman.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define WARPDIAG_MANID		5120
#define WARPDIAG_PRODID_FB	100
#define WARPDIAG_PRODID_REG	101

/* Display block of the control aperture; the mailbox starts at 0x1000. */
#define WARPDIAG_REG_WINDOW	0x1000UL
/* Usable framebuffer memory reported by csgfx.card. */
#define WARPDIAG_FB_USABLE	0x01800000UL

/* Register offsets (see sys/arch/amiga/dev/warpgfxreg.h). */
#define WARPDIAG_FB_OFFSET	0x000
#define WARPDIAG_FORMAT_PITCH	0x004
#define WARPDIAG_BLT_STATUS	0x024
#define WARPDIAG_OUTPUT_AUX	0x030
#define WARPDIAG_H_ACTIVE	0x100
#define WARPDIAG_V_ACTIVE	0x10c
#define WARPDIAG_HV_TOTAL	0x118
#define WARPDIAG_MODE		0x11c
#define WARPDIAG_SCALE		0x128
#define WARPDIAG_CLOCK_STATUS	0x200
#define WARPDIAG_CLOCK_CONTROL	0x204
#define WARPDIAG_INT_STATUS	0x208
#define WARPDIAG_INT_CONTROL	0x20c

#define WARPDIAG_CLOCK_READY	0x00000002U
#define WARPDIAG_VSYNC		0x00000002U	/* WARPDIAG_INT_STATUS */

/* Pixel clocks listed by csgfx.card 22.96 (firmware 2296), in Hz. */
static const unsigned long warpdiag_clock_hz[6] = {
	25175000UL, 40000000UL, 65000000UL,
	74250000UL, 108000000UL, 148500000UL,
};

struct warpdiag {
	int fd;
	int writable;
	unsigned long reg_pa;
	volatile uint32_t *reg;
};

#define WARPDIAG_RD(d, off)	((d)->reg[(off) / 4])
#define WARPDIAG_WR(d, off, v)	((d)->reg[(off) / 4] = (uint32_t)(v))

/*
 * Return the physical address printed for Zorro product PRODID in a kernel
 * message stream, or 0.  The last match wins, so the current boot's line is
 * used if a log holds several boots.
 */
static inline unsigned long
warpdiag_scan(FILE *fp, int prodid)
{
	char line[512], key[32], *k, *p, *end;
	unsigned long found = 0, value;
	size_t keylen;

	snprintf(key, sizeof(key), "man/pro %d/%d", WARPDIAG_MANID, prodid);
	keylen = strlen(key);
	while (fgets(line, sizeof(line), fp) != NULL) {
		if ((k = strstr(line, key)) == NULL)
			continue;
		/* Reject longer product numbers such as 5120/1010. */
		if (k[keylen] != ':' && k[keylen] != ' ' &&
		    k[keylen] != '\n' && k[keylen] != '\0')
			continue;
		*k = '\0';
		if ((p = strstr(line, "pa 0x")) == NULL)
			continue;
		errno = 0;
		value = strtoul(p + 3, &end, 16);
		if (errno == 0 && end != p + 3 && value != 0)
			found = value;
	}
	return found;
}

static inline unsigned long
warpdiag_find_pa(int prodid)
{
	const char *var, *env;
	unsigned long pa = 0;
	char *end;
	FILE *fp;

	var = prodid == WARPDIAG_PRODID_FB ? "WARPGFX_FB_PA" : "WARPGFX_REG_PA";
	if ((env = getenv(var)) != NULL && *env != '\0') {
		errno = 0;
		pa = strtoul(env, &end, 0);
		if (errno != 0 || *end != '\0' || pa == 0 || (pa & 0xfff) != 0)
			errx(2, "%s must be a page-aligned physical address", var);
		return pa;
	}

	if ((fp = fopen("/var/run/dmesg.boot", "r")) != NULL) {
		pa = warpdiag_scan(fp, prodid);
		fclose(fp);
	}
	if (pa == 0 && (fp = popen("/sbin/dmesg", "r")) != NULL) {
		pa = warpdiag_scan(fp, prodid);
		pclose(fp);
	}
	if (pa == 0)
		errx(1, "Zorro product %d/%d not found in the kernel messages; "
		    "set %s", WARPDIAG_MANID, prodid, var);
	return pa;
}

static inline void
warpdiag_open(struct warpdiag *d, int writable)
{
	void *va;

	d->writable = writable;
	d->reg_pa = warpdiag_find_pa(WARPDIAG_PRODID_REG);
	d->fd = open("/dev/mem", writable ? O_RDWR : O_RDONLY);
	if (d->fd == -1) {
		if (writable && (errno == EPERM || errno == EACCES))
			errx(1, "/dev/mem: %s; register writes need root and "
			    "kern.securelevel <= 0 (see diag/README.md)",
			    strerror(errno));
		err(1, "/dev/mem");
	}
	va = mmap(NULL, WARPDIAG_REG_WINDOW,
	    PROT_READ | (writable ? PROT_WRITE : 0), MAP_SHARED, d->fd,
	    (off_t)d->reg_pa);
	if (va == MAP_FAILED)
		err(1, "mmap control registers at 0x%lx", d->reg_pa);
	d->reg = va;
}

/* Map the first LEN bytes of the framebuffer; LEN is limited to 24 MiB. */
static inline volatile uint32_t *
warpdiag_map_fb(struct warpdiag *d, size_t len)
{
	unsigned long pa;
	void *va;

	if (len == 0 || len > WARPDIAG_FB_USABLE)
		errx(2, "framebuffer mapping must be 1..%lu bytes",
		    WARPDIAG_FB_USABLE);
	pa = warpdiag_find_pa(WARPDIAG_PRODID_FB);
	va = mmap(NULL, len, PROT_READ | (d->writable ? PROT_WRITE : 0),
	    MAP_SHARED, d->fd, (off_t)pa);
	if (va == MAP_FAILED)
		err(1, "mmap framebuffer at 0x%lx", pa);
	return va;
}

static inline void
warpdiag_close(struct warpdiag *d)
{
	munmap((void *)(uintptr_t)d->reg, WARPDIAG_REG_WINDOW);
	close(d->fd);
}

/* Parse an unsigned number (decimal, 0x hex, or 0 octal) or exit. */
static inline unsigned long
warpdiag_number(const char *s)
{
	unsigned long v;
	char *end;

	errno = 0;
	v = strtoul(s, &end, 0);
	if (*s == '\0' || *end != '\0' || errno != 0)
		errx(2, "invalid number: %s", s);
	return v;
}

#endif /* WARPDIAG_H */
