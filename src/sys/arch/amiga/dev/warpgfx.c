/*	$NetBSD$	*/

/*
 * Copyright (c) 2020 The NetBSD Foundation, Inc.
 * All rights reserved.
 *
 * This code is derived from software contributed to The NetBSD Foundation
 * by Alain Runa.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*-
 * Copyright (c) 2026 Carlos Milán Figueredo
 * with assistance from OpenAI gpt-5.6-sol
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/cdefs.h>
__KERNEL_RCSID(0, "$NetBSD$");

#include <sys/param.h>
#include <sys/bus.h>
#include <sys/device.h>
#include <sys/errno.h>
#include <sys/stdbool.h>
#include <sys/stdint.h>
#include <sys/sysctl.h>
#include <sys/systm.h>
#include <sys/types.h>

#include <dev/cons.h>
#include <dev/rasops/rasops.h>
#include <dev/wscons/wsconsio.h>
#include <dev/wscons/wsdisplay_vconsvar.h>
#include <dev/wscons/wsdisplayvar.h>
#include <dev/wsfont/wsfont.h>

#include <amiga/amiga/device.h>
#include <amiga/dev/kbdvar.h>
#include <amiga/dev/warpgfxreg.h>
#include <amiga/dev/zbusvar.h>

#include "opt_warpgfx.h"

#include "kbd.h"

#ifndef WARPGFX_MODE
#define WARPGFX_MODE		WARPGFX_MODE_720P
#endif

#if WARPGFX_MODE != WARPGFX_MODE_480P && \
    WARPGFX_MODE != WARPGFX_MODE_600P && \
    WARPGFX_MODE != WARPGFX_MODE_720P && \
    WARPGFX_MODE != WARPGFX_MODE_768P && \
    WARPGFX_MODE != WARPGFX_MODE_1024P && \
    WARPGFX_MODE != WARPGFX_MODE_1080P
#error "WARPGFX_MODE must be 480, 600, 720, 768, 1024, or 1080"
#endif

#define WARPGFX_PART_FB		0x01
#define WARPGFX_PART_REG	0x02
#define WARPGFX_PARTS_ALL	(WARPGFX_PART_FB | WARPGFX_PART_REG)

#define WARPGFX_CURSOR_RED_MASK		0xf800U

#define WARPGFX_BLT_WAIT_LOOPS		1000000

struct warpgfx_part {
	bool valid;
	void *pa;
	void *va;
	size_t size;
	int serno;
};

struct warpgfx_mode {
	const char *name;
	u_int width;
	u_int height;
	u_int depth;
	u_int stride;
	uint32_t clock_select;
	uint32_t clock_control;
	uint32_t format_pitch;
	uint32_t h_active;
	uint32_t h_timing_1;
	uint32_t h_timing_2;
	uint32_t v_active;
	uint32_t v_timing_1;
	uint32_t v_timing_2;
	uint32_t hv_total;
};

#if WARPGFX_MODE == WARPGFX_MODE_480P
static const struct warpgfx_mode warpgfx_console_mode = {
	.name = "640x480p75",
	.width = 640,
	.height = 480,
	.depth = WARPGFX_DEPTH,
	.stride = 640 * sizeof(uint16_t),
	.clock_select = WARPGFX_480P_CLOCK_SELECT,
	.clock_control = WARPGFX_480P_CLOCK_CONTROL,
	.format_pitch = WARPGFX_480P_FORMAT_PITCH,
	.h_active = WARPGFX_480P_H_ACTIVE,
	.h_timing_1 = WARPGFX_480P_H_TIMING_1,
	.h_timing_2 = WARPGFX_480P_H_TIMING_2,
	.v_active = WARPGFX_480P_V_ACTIVE,
	.v_timing_1 = WARPGFX_480P_V_TIMING_1,
	.v_timing_2 = WARPGFX_480P_V_TIMING_2,
	.hv_total = WARPGFX_480P_HV_TOTAL,
};
#elif WARPGFX_MODE == WARPGFX_MODE_600P
static const struct warpgfx_mode warpgfx_console_mode = {
	.name = "800x600p60",
	.width = 800,
	.height = 600,
	.depth = WARPGFX_DEPTH,
	.stride = 800 * sizeof(uint16_t),
	.clock_select = WARPGFX_600P_CLOCK_SELECT,
	.clock_control = WARPGFX_600P_CLOCK_CONTROL,
	.format_pitch = WARPGFX_600P_FORMAT_PITCH,
	.h_active = WARPGFX_600P_H_ACTIVE,
	.h_timing_1 = WARPGFX_600P_H_TIMING_1,
	.h_timing_2 = WARPGFX_600P_H_TIMING_2,
	.v_active = WARPGFX_600P_V_ACTIVE,
	.v_timing_1 = WARPGFX_600P_V_TIMING_1,
	.v_timing_2 = WARPGFX_600P_V_TIMING_2,
	.hv_total = WARPGFX_600P_HV_TOTAL,
};
#elif WARPGFX_MODE == WARPGFX_MODE_720P
static const struct warpgfx_mode warpgfx_console_mode = {
	.name = "1280x720p60",
	.width = 1280,
	.height = 720,
	.depth = WARPGFX_DEPTH,
	.stride = 1280 * sizeof(uint16_t),
	.clock_select = WARPGFX_720P_CLOCK_SELECT,
	.clock_control = WARPGFX_720P_CLOCK_CONTROL,
	.format_pitch = WARPGFX_720P_FORMAT_PITCH,
	.h_active = WARPGFX_720P_H_ACTIVE,
	.h_timing_1 = WARPGFX_720P_H_TIMING_1,
	.h_timing_2 = WARPGFX_720P_H_TIMING_2,
	.v_active = WARPGFX_720P_V_ACTIVE,
	.v_timing_1 = WARPGFX_720P_V_TIMING_1,
	.v_timing_2 = WARPGFX_720P_V_TIMING_2,
	.hv_total = WARPGFX_720P_HV_TOTAL,
};
#elif WARPGFX_MODE == WARPGFX_MODE_768P
static const struct warpgfx_mode warpgfx_console_mode = {
	.name = "1024x768p60",
	.width = 1024,
	.height = 768,
	.depth = WARPGFX_DEPTH,
	.stride = 1024 * sizeof(uint16_t),
	.clock_select = WARPGFX_768P_CLOCK_SELECT,
	.clock_control = WARPGFX_768P_CLOCK_CONTROL,
	.format_pitch = WARPGFX_768P_FORMAT_PITCH,
	.h_active = WARPGFX_768P_H_ACTIVE,
	.h_timing_1 = WARPGFX_768P_H_TIMING_1,
	.h_timing_2 = WARPGFX_768P_H_TIMING_2,
	.v_active = WARPGFX_768P_V_ACTIVE,
	.v_timing_1 = WARPGFX_768P_V_TIMING_1,
	.v_timing_2 = WARPGFX_768P_V_TIMING_2,
	.hv_total = WARPGFX_768P_HV_TOTAL,
};
#elif WARPGFX_MODE == WARPGFX_MODE_1024P
static const struct warpgfx_mode warpgfx_console_mode = {
	.name = "1280x1024p60",
	.width = 1280,
	.height = 1024,
	.depth = WARPGFX_DEPTH,
	.stride = 1280 * sizeof(uint16_t),
	.clock_select = WARPGFX_1024P_CLOCK_SELECT,
	.clock_control = WARPGFX_1024P_CLOCK_CONTROL,
	.format_pitch = WARPGFX_1024P_FORMAT_PITCH,
	.h_active = WARPGFX_1024P_H_ACTIVE,
	.h_timing_1 = WARPGFX_1024P_H_TIMING_1,
	.h_timing_2 = WARPGFX_1024P_H_TIMING_2,
	.v_active = WARPGFX_1024P_V_ACTIVE,
	.v_timing_1 = WARPGFX_1024P_V_TIMING_1,
	.v_timing_2 = WARPGFX_1024P_V_TIMING_2,
	.hv_total = WARPGFX_1024P_HV_TOTAL,
};
#else /* WARPGFX_MODE == WARPGFX_MODE_1080P */
static const struct warpgfx_mode warpgfx_console_mode = {
	.name = "1920x1080p60",
	.width = 1920,
	.height = 1080,
	.depth = WARPGFX_DEPTH,
	.stride = 1920 * sizeof(uint16_t),
	.clock_select = WARPGFX_1080P_CLOCK_SELECT,
	.clock_control = WARPGFX_1080P_CLOCK_CONTROL,
	.format_pitch = WARPGFX_1080P_FORMAT_PITCH,
	.h_active = WARPGFX_1080P_H_ACTIVE,
	.h_timing_1 = WARPGFX_1080P_H_TIMING_1,
	.h_timing_2 = WARPGFX_1080P_H_TIMING_2,
	.v_active = WARPGFX_1080P_V_ACTIVE,
	.v_timing_1 = WARPGFX_1080P_V_TIMING_1,
	.v_timing_2 = WARPGFX_1080P_V_TIMING_2,
	.hv_total = WARPGFX_1080P_HV_TOTAL,
};
#endif

struct warpgfx_softc {
	device_t sc_dev;
	const struct warpgfx_mode *sc_mode;

	struct bus_space_tag sc_reg_bst;
	bus_space_tag_t sc_regt;
	bus_space_handle_t sc_regh;
	volatile uint32_t *sc_regva;

	struct bus_space_tag sc_fb_bst;
	bus_space_tag_t sc_fbt;
	bus_space_handle_t sc_fbh;
	bus_addr_t sc_fbpa;
	size_t sc_fbsize;

	struct vcons_screen sc_console_screen;
	struct vcons_data sc_vd;
	struct wsscreen_descr sc_defaultscreen;
	struct wsscreen_descr sc_80x25screen;
	struct wsscreen_descr sc_80x27screen;
	struct wsscreen_list sc_screenlist;
	const struct wsscreen_descr *sc_screens[3];

	u_int sc_wsmode;
	u_int sc_width;
	u_int sc_height;
	u_int sc_depth;
	u_int sc_stride;
	bool sc_isconsole;

#ifdef WARPGFX_ACCEL
	struct wsdisplay_emulops sc_swops;
	bool sc_accel_ok;
	uint32_t sc_blt_serial;
#endif
};

static struct warpgfx_part warpgfx_fb_part;
static struct warpgfx_part warpgfx_reg_part;
static uint8_t warpgfx_early_parts;
static bool warpgfx_exists;

static int warpgfx_match(device_t, cfdata_t, void *);
static void warpgfx_attach(device_t, device_t, void *);
static void warpgfx_deferred(device_t);

static void warpgfx_reset(struct warpgfx_softc *);
static bool warpgfx_set_clock(struct warpgfx_softc *);
static void warpgfx_set_mode(struct warpgfx_softc *);
#ifdef WARPGFX_DEBUG
static void warpgfx_dump_regs(struct warpgfx_softc *, const char *);
#endif
static void warpgfx_attach_wsdisplay(struct warpgfx_softc *);
static void warpgfx_init_screen(void *, struct vcons_screen *, int, long *);
static void warpgfx_do_cursor(struct rasops_info *);

#ifdef WARPGFX_ACCEL
static bool warpgfx_wait_blitter(struct warpgfx_softc *);
static bool warpgfx_rectfill(struct warpgfx_softc *, uint16_t, uint16_t,
    uint16_t, uint16_t, uint16_t);
static bool warpgfx_bitblt(struct warpgfx_softc *, uint16_t, uint16_t,
    uint16_t, uint16_t, uint16_t, uint16_t);
static bool warpgfx_valid_rect(struct warpgfx_softc *, uint32_t, uint32_t,
    uint32_t, uint32_t);
static void warpgfx_software_copy(struct warpgfx_softc *, uint32_t,
    uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
static int warpgfx_wsfb_blit(struct warpgfx_softc *,
    struct wsdisplayio_blit *);
static void warpgfx_eraserows(void *, int, int, long);
static void warpgfx_copyrows(void *, int, int, int);
static void warpgfx_erasecols(void *, int, int, int, long);
static void warpgfx_copycols(void *, int, int, int, int);
#endif

static int warpgfx_ioctl(void *, void *, u_long, void *, int, struct lwp *);
static paddr_t warpgfx_mmap(void *, void *, off_t, int);
static int warpgfx_get_fbinfo(struct warpgfx_softc *,
    struct wsdisplayio_fbinfo *);

void warpgfxcnprobe(struct consdev *);
void warpgfxcninit(struct consdev *);
void warpgfxcnpollc(dev_t, int);
void warpgfxcnputc(dev_t, int);
int warpgfxcngetc(dev_t);

CFATTACH_DECL_NEW(warpgfx, sizeof(struct warpgfx_softc),
    warpgfx_match, warpgfx_attach, NULL, NULL);

/*
 * Expose the driver software version as a read-only string sysctl,
 * hw.warpgfx.version, so it can be queried from userland (e.g.
 * "sysctl hw.warpgfx.version") without emitting anything at boot.
 */
static const char warpgfx_version[] = WARPGFX_VERSION;

SYSCTL_SETUP(sysctl_hw_warpgfx_setup, "sysctl hw.warpgfx setup")
{
	const struct sysctlnode *rnode = NULL;

	if (sysctl_createv(clog, 0, NULL, &rnode,
	    CTLFLAG_PERMANENT, CTLTYPE_NODE, "warpgfx",
	    SYSCTL_DESCR("CS-Lab Warp GFX driver"),
	    NULL, 0, NULL, 0, CTL_HW, CTL_CREATE, CTL_EOL) != 0)
		return;

	(void)sysctl_createv(clog, 0, &rnode, NULL,
	    CTLFLAG_PERMANENT | CTLFLAG_READONLY, CTLTYPE_STRING, "version",
	    SYSCTL_DESCR("WarpGFX driver version"),
	    NULL, 0, __UNCONST(warpgfx_version), 0, CTL_CREATE, CTL_EOL);
}

static struct wsdisplay_accessops warpgfx_accessops = {
	.ioctl = warpgfx_ioctl,
	.mmap = warpgfx_mmap,
};

/* Direct volatile MMIO matches the accesses made by csgfx.card. */
#define WARPGFX_READ(sc, reg) \
	((sc)->sc_regva[(reg) / sizeof(uint32_t)])
#define WARPGFX_WRITE(sc, reg, val) do { \
	(sc)->sc_regva[(reg) / sizeof(uint32_t)] = (uint32_t)(val); \
} while (0)

static int
warpgfx_match(device_t parent, cfdata_t cf, void *aux)
{
	struct zbus_args *zap = aux;
	uint8_t part;

	if (zap->manid != WARPGFX_MANID)
		return 0;

	switch (zap->prodid) {
	case WARPGFX_PRODID_FB:
		part = WARPGFX_PART_FB;
		break;
	case WARPGFX_PRODID_REG:
		part = WARPGFX_PART_REG;
		break;
	default:
		return 0;
	}

	if (amiga_realconfig == 0) {
		warpgfx_early_parts |= part;
		warpgfx_exists =
		    (warpgfx_early_parts & WARPGFX_PARTS_ALL) ==
		    WARPGFX_PARTS_ALL;
		return 0;
	}

	return 1;
}

static void
warpgfx_attach(device_t parent, device_t self, void *aux)
{
	struct zbus_args *zap = aux;
	struct warpgfx_part *part;

	if (zap->prodid == WARPGFX_PRODID_FB) {
		part = &warpgfx_fb_part;
		aprint_normal(": CS-Lab Warp GFX framebuffer, %d MB aperture\n",
		    zap->size / (1024 * 1024));
	} else {
		part = &warpgfx_reg_part;
		aprint_normal(": CS-Lab Warp GFX control registers\n");
	}

	part->valid = true;
	part->pa = zap->pa;
	part->va = zap->va;
	part->size = zap->size;
	part->serno = zap->serno;

	/*
	 * Product 101 owns the wsdisplay instance.  Deferring its completion
	 * until zbus has attached all children makes product ordering irrelevant.
	 */
	if (zap->prodid == WARPGFX_PRODID_REG)
		config_defer(self, warpgfx_deferred);
}

static void
warpgfx_deferred(device_t self)
{
	struct warpgfx_softc *sc = device_private(self);
	size_t visible_size;

	if (!warpgfx_fb_part.valid || !warpgfx_reg_part.valid) {
		aprint_error_dev(self,
		    "both framebuffer and control functions are required\n");
		return;
	}

	if (warpgfx_reg_part.size < WARPGFX_REG_SIZE) {
		aprint_error_dev(self, "control aperture is only %zu bytes\n",
		    warpgfx_reg_part.size);
		return;
	}

	sc->sc_dev = self;
	sc->sc_mode = &warpgfx_console_mode;
	sc->sc_width = sc->sc_mode->width;
	sc->sc_height = sc->sc_mode->height;
	sc->sc_depth = sc->sc_mode->depth;
	sc->sc_stride = sc->sc_mode->stride;
	visible_size = sc->sc_stride * sc->sc_height;

	sc->sc_fbsize = MIN(warpgfx_fb_part.size,
	    (size_t)WARPGFX_FB_USABLE_SIZE);
	if (sc->sc_fbsize < visible_size) {
		aprint_error_dev(self,
		    "framebuffer is too small for %s, 16 bpp\n",
		    sc->sc_mode->name);
		return;
	}

	sc->sc_reg_bst.base = (bus_addr_t)warpgfx_reg_part.va;
	sc->sc_reg_bst.absm = &amiga_bus_stride_1;
	sc->sc_regt = &sc->sc_reg_bst;
	if (bus_space_map(sc->sc_regt, 0, WARPGFX_REG_SIZE, 0,
	    &sc->sc_regh)) {
		aprint_error_dev(self, "unable to map control registers\n");
		return;
	}
	sc->sc_regva = bus_space_vaddr(sc->sc_regt, sc->sc_regh);
	if (sc->sc_regva == NULL) {
		aprint_error_dev(self, "control registers are not linear\n");
		return;
	}
#ifdef WARPGFX_DEBUG
	aprint_normal_dev(self, "register aperture pa %p, va 0x%08lx\n",
	    warpgfx_reg_part.pa, (u_long)(uintptr_t)sc->sc_regva);
	warpgfx_dump_regs(sc, "initial");
#endif

	sc->sc_fb_bst.base = (bus_addr_t)warpgfx_fb_part.va;
	sc->sc_fb_bst.absm = &amiga_bus_stride_1;
	sc->sc_fbt = &sc->sc_fb_bst;
	if (bus_space_map(sc->sc_fbt, 0, sc->sc_fbsize,
	    BUS_SPACE_MAP_LINEAR, &sc->sc_fbh)) {
		aprint_error_dev(self, "unable to map framebuffer\n");
		return;
	}
	sc->sc_fbpa = (bus_addr_t)warpgfx_fb_part.pa;

	warpgfx_reset(sc);
#ifdef WARPGFX_DEBUG
	warpgfx_dump_regs(sc, "after reset");
#endif
	if (!warpgfx_set_clock(sc))
		return;
#ifdef WARPGFX_DEBUG
	warpgfx_dump_regs(sc, "after clock");
#endif
	memset(bus_space_vaddr(sc->sc_fbt, sc->sc_fbh), 0, visible_size);
	warpgfx_set_mode(sc);
#ifdef WARPGFX_DEBUG
	warpgfx_dump_regs(sc, "after mode");
#endif

	aprint_normal_dev(self,
	    "%s, %u bpp, stride %u, %zu MB usable video memory\n",
	    sc->sc_mode->name, sc->sc_depth, sc->sc_stride,
	    sc->sc_fbsize / (1024 * 1024));

#ifdef WARPGFX_ACCEL
	sc->sc_accel_ok = warpgfx_wait_blitter(sc);
	if (sc->sc_accel_ok)
		aprint_normal_dev(self,
		    "2D console/wsfb acceleration enabled\n");
	else
		aprint_error_dev(self,
		    "2D engine is busy; using software raster operations\n");
#endif

	warpgfx_attach_wsdisplay(sc);
}

static void
warpgfx_reset(struct warpgfx_softc *sc)
{
	u_int i;

	/* Sequence used by csgfx.card before enabling the first mode. */
	WARPGFX_WRITE(sc, WARPGFX_REG_COMMAND_RESET, 0);
	for (i = 0; i < 0x0c00; i++)
		WARPGFX_WRITE(sc, WARPGFX_REG_COMMAND, 0);
}

static bool
warpgfx_set_clock(struct warpgfx_softc *sc)
{
	const struct warpgfx_mode *mode = sc->sc_mode;
	uint32_t value;
	u_int i;

	value = WARPGFX_READ(sc, WARPGFX_REG_CLOCK_CONTROL);
	if ((value & WARPGFX_CLOCK_SELECT_MASK) ==
	    mode->clock_select &&
	    (WARPGFX_READ(sc, WARPGFX_REG_CLOCK_STATUS) &
	    WARPGFX_CLOCK_READY) != 0)
		return true;

	WARPGFX_WRITE(sc, WARPGFX_REG_CLOCK_CONTROL,
	    mode->clock_control);
	for (i = 0; i < 1000000; i++) {
		if ((WARPGFX_READ(sc, WARPGFX_REG_CLOCK_STATUS) &
		    WARPGFX_CLOCK_READY) != 0)
			return true;
	}

	aprint_error_dev(sc->sc_dev,
	    "%s pixel clock did not lock: status %08x control %08x\n",
	    mode->name,
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_CLOCK_STATUS),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_CLOCK_CONTROL));
	return false;
}

static void
warpgfx_set_mode(struct warpgfx_softc *sc)
{
	const struct warpgfx_mode *mode = sc->sc_mode;
	uint32_t value;

	value = WARPGFX_READ(sc, WARPGFX_REG_SCALE_CONTROL);
	value &= ~0x0000003cU;
	WARPGFX_WRITE(sc, WARPGFX_REG_SCALE_CONTROL, value);

	WARPGFX_WRITE(sc, WARPGFX_REG_OUTPUT_AUX, 0);
	WARPGFX_WRITE(sc, WARPGFX_REG_FB_OFFSET, 0);
	WARPGFX_WRITE(sc, WARPGFX_REG_FORMAT_PITCH, mode->format_pitch);
	WARPGFX_WRITE(sc, WARPGFX_REG_H_ACTIVE, mode->h_active);
	WARPGFX_WRITE(sc, WARPGFX_REG_H_TIMING_1, mode->h_timing_1);
	WARPGFX_WRITE(sc, WARPGFX_REG_H_TIMING_2, mode->h_timing_2);
	WARPGFX_WRITE(sc, WARPGFX_REG_V_ACTIVE, mode->v_active);
	WARPGFX_WRITE(sc, WARPGFX_REG_V_TIMING_1, mode->v_timing_1);
	WARPGFX_WRITE(sc, WARPGFX_REG_V_TIMING_2, mode->v_timing_2);
	WARPGFX_WRITE(sc, WARPGFX_REG_HV_TOTAL, mode->hv_total);
	WARPGFX_WRITE(sc, WARPGFX_REG_MODE_COMMIT, WARPGFX_MODE_COMMIT);
	WARPGFX_WRITE(sc, WARPGFX_REG_MODE_COMMIT, WARPGFX_MODE_ENABLE);

	bus_space_barrier(sc->sc_regt, sc->sc_regh, 0,
	    WARPGFX_REG_SIZE, BUS_SPACE_BARRIER_WRITE);
}

#ifdef WARPGFX_DEBUG
static void
warpgfx_dump_regs(struct warpgfx_softc *sc, const char *where)
{
	uint32_t bus00, bus04, bus11c;

	bus00 = bus_space_read_4(sc->sc_regt, sc->sc_regh,
	    WARPGFX_REG_FB_OFFSET);
	bus04 = bus_space_read_4(sc->sc_regt, sc->sc_regh,
	    WARPGFX_REG_FORMAT_PITCH);
	bus11c = bus_space_read_4(sc->sc_regt, sc->sc_regh,
	    WARPGFX_REG_MODE_COMMIT);

	aprint_normal_dev(sc->sc_dev,
	    "%s: direct 000=%08x 004=%08x 11c=%08x; "
	    "bus 000=%08x 004=%08x 11c=%08x\n",
	    where,
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_FB_OFFSET),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_FORMAT_PITCH),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_MODE_COMMIT),
	    (unsigned)bus00, (unsigned)bus04, (unsigned)bus11c);
	aprint_normal_dev(sc->sc_dev,
	    "%s: 030=%08x 100=%08x 104=%08x 108=%08x\n", where,
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_OUTPUT_AUX),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_H_ACTIVE),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_H_TIMING_1),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_H_TIMING_2));
	aprint_normal_dev(sc->sc_dev,
	    "%s: 10c=%08x 110=%08x 114=%08x 118=%08x 128=%08x\n",
	    where,
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_V_ACTIVE),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_V_TIMING_1),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_V_TIMING_2),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_HV_TOTAL),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_SCALE_CONTROL));
	aprint_normal_dev(sc->sc_dev,
	    "%s: clock 200=%08x 204=%08x; interrupt 208=%08x 20c=%08x\n",
	    where,
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_CLOCK_STATUS),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_CLOCK_CONTROL),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_INTERRUPT_STATUS),
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_INTERRUPT_CONTROL));
	aprint_normal_dev(sc->sc_dev,
	    "%s: blitter status 024=%08x\n", where,
	    (unsigned)WARPGFX_READ(sc, WARPGFX_REG_BLT_STATUS));
}
#endif

static void
warpgfx_attach_wsdisplay(struct warpgfx_softc *sc)
{
	struct rasops_info *ri;
	struct wsemuldisplaydev_attach_args ws_aa;
	long defattr;

#ifdef WARPGFX_CONSOLE
	sc->sc_isconsole = true;
#else
	sc->sc_isconsole = false;
#endif

	sc->sc_defaultscreen = (struct wsscreen_descr) {
	    "default", 0, 0, NULL, 8, 16,
	    WSSCREEN_WSCOLORS | WSSCREEN_HILIT, NULL
	};
	sc->sc_80x25screen = (struct wsscreen_descr) {
	    "80x25", 80, 25, NULL, 8, 16,
	    WSSCREEN_WSCOLORS | WSSCREEN_HILIT, NULL
	};
	sc->sc_80x27screen = (struct wsscreen_descr) {
	    "80x27", 80, 27, NULL, 8, 16,
	    WSSCREEN_WSCOLORS | WSSCREEN_HILIT, NULL
	};
	sc->sc_screens[0] = &sc->sc_defaultscreen;
	sc->sc_screens[1] = &sc->sc_80x25screen;
	sc->sc_screens[2] = &sc->sc_80x27screen;
	sc->sc_screenlist = (struct wsscreen_list) {
	    3, sc->sc_screens
	};
	sc->sc_wsmode = WSDISPLAYIO_MODE_EMUL;

	vcons_init(&sc->sc_vd, sc, &sc->sc_defaultscreen,
	    &warpgfx_accessops);
	sc->sc_vd.init_screen = warpgfx_init_screen;
	ri = &sc->sc_console_screen.scr_ri;

	vcons_init_screen(&sc->sc_vd, &sc->sc_console_screen, 1,
	    &defattr);
	sc->sc_console_screen.scr_flags |= VCONS_SCREEN_IS_STATIC;

	sc->sc_defaultscreen.textops = &ri->ri_ops;
	sc->sc_defaultscreen.capabilities = ri->ri_caps;
	sc->sc_defaultscreen.nrows = ri->ri_rows;
	sc->sc_defaultscreen.ncols = ri->ri_cols;
	sc->sc_defaultscreen.fontwidth = ri->ri_font->fontwidth;
	sc->sc_defaultscreen.fontheight = ri->ri_font->fontheight;
	sc->sc_80x25screen.textops = &ri->ri_ops;
	sc->sc_80x25screen.capabilities = ri->ri_caps;
	sc->sc_80x27screen.textops = &ri->ri_ops;
	sc->sc_80x27screen.capabilities = ri->ri_caps;

	if (sc->sc_isconsole) {
		vcons_redraw_screen(&sc->sc_console_screen);

		wsdisplay_cnattach(&sc->sc_defaultscreen, ri, 0, 0,
		    defattr);
		vcons_replay_msgbuf(&sc->sc_console_screen);
	}

	ws_aa.console = sc->sc_isconsole;
	ws_aa.scrdata = &sc->sc_screenlist;
	ws_aa.accessops = &warpgfx_accessops;
	ws_aa.accesscookie = &sc->sc_vd;

	config_found(sc->sc_dev, &ws_aa, wsemuldisplaydevprint, CFARGS_NONE);
}

static void
warpgfx_init_screen(void *cookie, struct vcons_screen *scr, int existing,
    long *defattr)
{
	struct warpgfx_softc *sc = cookie;
	struct rasops_info *ri = &scr->scr_ri;
	bool fixed_geometry;

	scr->scr_flags |= VCONS_LOADFONT;
	wsfont_init();
	fixed_geometry = scr->scr_type != NULL &&
	    scr->scr_type != &sc->sc_defaultscreen;

	ri->ri_bits = bus_space_vaddr(sc->sc_fbt, sc->sc_fbh);
	ri->ri_depth = sc->sc_depth;
	ri->ri_width = sc->sc_width;
	ri->ri_height = sc->sc_height;
	ri->ri_stride = sc->sc_stride;
	ri->ri_flg = fixed_geometry ? RI_CENTER : 0;

	/* csgfx RGB format 10 is big-endian R5G6B5. */
	ri->ri_rnum = 5;
	ri->ri_gnum = 6;
	ri->ri_bnum = 5;
	ri->ri_rpos = 11;
	ri->ri_gpos = 5;
	ri->ri_bpos = 0;

	if (fixed_geometry) {
		rasops_init(ri, scr->scr_type->nrows,
		    scr->scr_type->ncols);
	} else {
		rasops_init(ri, 0, 0);
	}
	ri->ri_caps = WSSCREEN_WSCOLORS;
	if (!fixed_geometry) {
		rasops_reconfig(ri,
		    ri->ri_height / ri->ri_font->fontheight,
		    ri->ri_width / ri->ri_font->fontwidth);
	}
	ri->ri_hw = scr;

	ri->ri_do_cursor = warpgfx_do_cursor;

#ifdef WARPGFX_ACCEL
	sc->sc_swops = ri->ri_ops;
	ri->ri_ops.eraserows = warpgfx_eraserows;
	ri->ri_ops.copyrows = warpgfx_copyrows;
	ri->ri_ops.erasecols = warpgfx_erasecols;
	ri->ri_ops.copycols = warpgfx_copycols;
#endif
}

static void
warpgfx_do_cursor(struct rasops_info *ri)
{
	struct vcons_screen *scr = ri->ri_hw;
	struct warpgfx_softc *sc = scr->scr_cookie;
	volatile uint16_t *dst;
	bus_size_t offset, size;
	u_int width, height, x, y;

	width = ri->ri_font->fontwidth;
	height = ri->ri_font->fontheight;
	offset = (ri->ri_yorigin + ri->ri_crow * height) * ri->ri_stride +
	    (ri->ri_xorigin + ri->ri_ccol * width) * sizeof(uint16_t);
	size = (height - 1) * ri->ri_stride + width * sizeof(uint16_t);
	if (offset + size > sc->sc_fbsize)
		return;

	/* Toggle only the red component, like the colored AGA wscons cursor. */
	for (y = 0; y < height; y++) {
		dst = (volatile uint16_t *)(ri->ri_origbits + offset +
		    y * ri->ri_stride);
		for (x = 0; x < width; x++)
			dst[x] ^= WARPGFX_CURSOR_RED_MASK;
	}

	bus_space_barrier(sc->sc_fbt, sc->sc_fbh, offset, size,
	    BUS_SPACE_BARRIER_WRITE);
}

#ifdef WARPGFX_ACCEL
static bool
warpgfx_wait_blitter(struct warpgfx_softc *sc)
{
	u_int i;

	for (i = 0; i < WARPGFX_BLT_WAIT_LOOPS; i++) {
		if ((WARPGFX_READ(sc, WARPGFX_REG_BLT_STATUS) &
		    WARPGFX_BLT_STATUS_BUSY_MASK) == 0)
			return true;
	}

	return false;
}

static bool
warpgfx_rectfill(struct warpgfx_softc *sc, uint16_t x, uint16_t y,
    uint16_t width, uint16_t height, uint16_t color)
{
	uint32_t address, xy, size;

	if (width == 0 || height == 0)
		return true;
	if (!sc->sc_accel_ok || !warpgfx_wait_blitter(sc)) {
		sc->sc_accel_ok = false;
		return false;
	}

	address = (uint32_t)(sc->sc_fbpa + y * sc->sc_stride +
	    x * sizeof(uint16_t));
	xy = ((uint32_t)y << 16) | x;
	size = ((uint32_t)height << 16) | width;

	/* This is the RGBFB_R5G6B5 FillRect sequence from csgfx.card. */
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_DST_STRIDE, sc->sc_stride);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_DST_ADDRESS, address);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_SIZE, size);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_DST_XY, xy);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_COLOR, color);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_COMMAND,
	    WARPGFX_BLT_COMMAND_FILL_16);
	bus_space_barrier(sc->sc_regt, sc->sc_regh,
	    WARPGFX_REG_BLT_SRC_ADDRESS,
	    WARPGFX_REG_OUTPUT_AUX - WARPGFX_REG_BLT_SRC_ADDRESS,
	    BUS_SPACE_BARRIER_WRITE);

	if (!warpgfx_wait_blitter(sc)) {
		sc->sc_accel_ok = false;
		return false;
	}
	return true;
}

static bool
warpgfx_bitblt(struct warpgfx_softc *sc, uint16_t src_x, uint16_t src_y,
    uint16_t dst_x, uint16_t dst_y, uint16_t width, uint16_t height)
{
	uint32_t src_address, dst_address, src_xy, dst_xy, size;

	/* csgfx.card sends one-pixel-wide operations to its CPU fallback. */
	if (width <= 1 || height <= 1)
		return false;
	if (!sc->sc_accel_ok || !warpgfx_wait_blitter(sc)) {
		sc->sc_accel_ok = false;
		return false;
	}

	src_address = (uint32_t)(sc->sc_fbpa + src_y * sc->sc_stride +
	    src_x * sizeof(uint16_t));
	dst_address = (uint32_t)(sc->sc_fbpa + dst_y * sc->sc_stride +
	    dst_x * sizeof(uint16_t));
	src_xy = ((uint32_t)src_y << 16) | src_x;
	dst_xy = ((uint32_t)dst_y << 16) | dst_x;
	size = ((uint32_t)height << 16) | width;

	/* RGBFB_R5G6B5 source-copy minterm sequence from csgfx.card. */
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_SRC_ADDRESS, src_address);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_DST_ADDRESS, dst_address);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_SIZE, size);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_SRC_XY, src_xy);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_DST_XY, dst_xy);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_SRC_STRIDE, sc->sc_stride);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_DST_STRIDE, sc->sc_stride);
	WARPGFX_WRITE(sc, WARPGFX_REG_BLT_COMMAND,
	    WARPGFX_BLT_COMMAND_COPY_16);
	bus_space_barrier(sc->sc_regt, sc->sc_regh,
	    WARPGFX_REG_BLT_SRC_ADDRESS,
	    WARPGFX_REG_OUTPUT_AUX - WARPGFX_REG_BLT_SRC_ADDRESS,
	    BUS_SPACE_BARRIER_WRITE);

	if (!warpgfx_wait_blitter(sc)) {
		sc->sc_accel_ok = false;
		return false;
	}
	return true;
}

static bool
warpgfx_valid_rect(struct warpgfx_softc *sc, uint32_t x, uint32_t y,
    uint32_t width, uint32_t height)
{
	uint32_t fb_width, fb_height;

	/* Off-screen pixmaps are extra rows using the scanout stride. */
	if (width == 0 || height == 0)
		return true;
	if (x > UINT16_MAX || y > UINT16_MAX || width > UINT16_MAX ||
	    height > UINT16_MAX)
		return false;

	fb_width = sc->sc_stride / sizeof(uint16_t);
	fb_height = sc->sc_fbsize / sc->sc_stride;
	if (x >= fb_width || y >= fb_height)
		return false;
	if (width > fb_width - x || height > fb_height - y)
		return false;

	return true;
}

static void
warpgfx_software_copy(struct warpgfx_softc *sc, uint32_t src_x,
    uint32_t src_y, uint32_t dst_x, uint32_t dst_y, uint32_t width,
    uint32_t height)
{
	uint8_t *fb;
	size_t barrier_size, dst_offset, length, src_offset;
	uint32_t row;

	if (width == 0 || height == 0)
		return;

	fb = bus_space_vaddr(sc->sc_fbt, sc->sc_fbh);
	length = width * sizeof(uint16_t);
	src_offset = src_y * sc->sc_stride + src_x * sizeof(uint16_t);
	dst_offset = dst_y * sc->sc_stride + dst_x * sizeof(uint16_t);

	if (dst_offset > src_offset) {
		for (row = height; row-- > 0;) {
			memmove(fb + dst_offset + row * sc->sc_stride,
			    fb + src_offset + row * sc->sc_stride, length);
		}
	} else {
		for (row = 0; row < height; row++) {
			memmove(fb + dst_offset + row * sc->sc_stride,
			    fb + src_offset + row * sc->sc_stride, length);
		}
	}

	barrier_size = (height - 1) * sc->sc_stride + length;
	bus_space_barrier(sc->sc_fbt, sc->sc_fbh, dst_offset,
	    barrier_size, BUS_SPACE_BARRIER_WRITE);
}

static int
warpgfx_wsfb_blit(struct warpgfx_softc *sc, struct wsdisplayio_blit *blit)
{
	bool done;

	if (sc->sc_wsmode == WSDISPLAYIO_MODE_EMUL)
		return EBUSY;
	if (!sc->sc_accel_ok)
		return EIO;

	switch (blit->op) {
	case WSFB_BLIT_FILL:
		if (!warpgfx_valid_rect(sc, blit->dstx, blit->dsty,
		    blit->width, blit->height))
			return EINVAL;
		done = warpgfx_rectfill(sc, (uint16_t)blit->dstx,
		    (uint16_t)blit->dsty, (uint16_t)blit->width,
		    (uint16_t)blit->height, (uint16_t)blit->pen);
		break;

	case WSFB_BLIT_COPY:
		if (!warpgfx_valid_rect(sc, blit->srcx, blit->srcy,
		    blit->width, blit->height) ||
		    !warpgfx_valid_rect(sc, blit->dstx, blit->dsty,
		    blit->width, blit->height))
			return EINVAL;
		if (blit->width <= 1 || blit->height <= 1) {
			warpgfx_software_copy(sc, blit->srcx, blit->srcy,
			    blit->dstx, blit->dsty, blit->width,
			    blit->height);
			done = true;
		} else {
			done = warpgfx_bitblt(sc, (uint16_t)blit->srcx,
			    (uint16_t)blit->srcy, (uint16_t)blit->dstx,
			    (uint16_t)blit->dsty, (uint16_t)blit->width,
			    (uint16_t)blit->height);
		}
		break;

	case WSFB_BLIT_TRANS:
		return EOPNOTSUPP;

	default:
		return EINVAL;
	}

	if (!done)
		return EIO;
	blit->serial = ++sc->sc_blt_serial;
	return 0;
}

static void
warpgfx_copyrows(void *cookie, int srcrow, int dstrow, int nrows)
{
	struct rasops_info *ri = cookie;
	struct vcons_screen *scr = ri->ri_hw;
	struct warpgfx_softc *sc = scr->scr_cookie;
	int x, src_y, dst_y, width, height;

	x = ri->ri_xorigin;
	src_y = ri->ri_yorigin + ri->ri_font->fontheight * srcrow;
	dst_y = ri->ri_yorigin + ri->ri_font->fontheight * dstrow;
	width = ri->ri_emuwidth;
	height = ri->ri_font->fontheight * nrows;
	if (sc->sc_wsmode == WSDISPLAYIO_MODE_EMUL &&
	    warpgfx_bitblt(sc, x, src_y, x, dst_y, width, height))
		return;

	sc->sc_swops.copyrows(cookie, srcrow, dstrow, nrows);
}

static void
warpgfx_eraserows(void *cookie, int row, int nrows, long fillattr)
{
	struct rasops_info *ri = cookie;
	struct vcons_screen *scr = ri->ri_hw;
	struct warpgfx_softc *sc = scr->scr_cookie;
	int x, y, width, height, fg, bg, ul;
	uint16_t color;

	x = ri->ri_xorigin;
	y = ri->ri_yorigin + ri->ri_font->fontheight * row;
	width = ri->ri_emuwidth;
	height = ri->ri_font->fontheight * nrows;
	rasops_unpack_attr(fillattr, &fg, &bg, &ul);
	color = (uint16_t)(ri->ri_devcmap[bg & 0x0f] & 0xffffU);
	if (sc->sc_wsmode == WSDISPLAYIO_MODE_EMUL &&
	    warpgfx_rectfill(sc, x, y, width, height, color))
		return;

	sc->sc_swops.eraserows(cookie, row, nrows, fillattr);
}

static void
warpgfx_copycols(void *cookie, int row, int srccol, int dstcol, int ncols)
{
	struct rasops_info *ri = cookie;
	struct vcons_screen *scr = ri->ri_hw;
	struct warpgfx_softc *sc = scr->scr_cookie;
	int src_x, dst_x, y, width, height;

	src_x = ri->ri_xorigin + ri->ri_font->fontwidth * srccol;
	dst_x = ri->ri_xorigin + ri->ri_font->fontwidth * dstcol;
	y = ri->ri_yorigin + ri->ri_font->fontheight * row;
	width = ri->ri_font->fontwidth * ncols;
	height = ri->ri_font->fontheight;
	if (sc->sc_wsmode == WSDISPLAYIO_MODE_EMUL &&
	    warpgfx_bitblt(sc, src_x, y, dst_x, y, width, height))
		return;

	sc->sc_swops.copycols(cookie, row, srccol, dstcol, ncols);
}

static void
warpgfx_erasecols(void *cookie, int row, int startcol, int ncols,
    long fillattr)
{
	struct rasops_info *ri = cookie;
	struct vcons_screen *scr = ri->ri_hw;
	struct warpgfx_softc *sc = scr->scr_cookie;
	int x, y, width, height, fg, bg, ul;
	uint16_t color;

	x = ri->ri_xorigin + ri->ri_font->fontwidth * startcol;
	y = ri->ri_yorigin + ri->ri_font->fontheight * row;
	width = ri->ri_font->fontwidth * ncols;
	height = ri->ri_font->fontheight;
	rasops_unpack_attr(fillattr, &fg, &bg, &ul);
	color = (uint16_t)(ri->ri_devcmap[bg & 0x0f] & 0xffffU);
	if (sc->sc_wsmode == WSDISPLAYIO_MODE_EMUL &&
	    warpgfx_rectfill(sc, x, y, width, height, color))
		return;

	sc->sc_swops.erasecols(cookie, row, startcol, ncols, fillattr);
}
#endif

static int
warpgfx_ioctl(void *v, void *vs, u_long cmd, void *data, int flag,
    struct lwp *l)
{
	struct vcons_data *vd = v;
	struct warpgfx_softc *sc = vd->cookie;
	u_int new_mode;

	switch (cmd) {
	case WSDISPLAYIO_GTYPE:
		*(u_int *)data = WSDISPLAY_TYPE_UNKNOWN;
		return 0;

	case WSDISPLAYIO_GET_FBINFO:
		return warpgfx_get_fbinfo(sc,
		    (struct wsdisplayio_fbinfo *)data);

	case WSDISPLAYIO_GINFO:
		((struct wsdisplay_fbinfo *)data)->width = sc->sc_width;
		((struct wsdisplay_fbinfo *)data)->height = sc->sc_height;
		((struct wsdisplay_fbinfo *)data)->depth = sc->sc_depth;
		((struct wsdisplay_fbinfo *)data)->cmsize = 0;
		return 0;

	case WSDISPLAYIO_LINEBYTES:
		*(u_int *)data = sc->sc_stride;
		return 0;

#ifdef WARPGFX_ACCEL
	case WSDISPLAYIO_DOBLIT:
		return warpgfx_wsfb_blit(sc,
		    (struct wsdisplayio_blit *)data);

	case WSDISPLAYIO_WAITBLIT:
		if (!sc->sc_accel_ok)
			return EIO;
		if (!warpgfx_wait_blitter(sc)) {
			sc->sc_accel_ok = false;
			return EIO;
		}
		((struct wsdisplayio_blit *)data)->serial =
		    sc->sc_blt_serial;
		return 0;
#endif

	case WSDISPLAYIO_GET_BUSID:
		((struct wsdisplayio_bus_id *)data)->bus_type =
		    WSDISPLAYIO_BUS_SOC;
		return 0;

	case WSDISPLAYIO_GVIDEO:
		*(int *)data = WSDISPLAYIO_VIDEO_ON;
		return 0;

	case WSDISPLAYIO_SVIDEO:
		if (*(int *)data == WSDISPLAYIO_VIDEO_ON)
			return 0;
		return EPASSTHROUGH;

	case WSDISPLAYIO_GMODE:
		*(u_int *)data = sc->sc_wsmode;
		return 0;

	case WSDISPLAYIO_SMODE:
		new_mode = *(u_int *)data;
		switch (new_mode) {
		case WSDISPLAYIO_MODE_EMUL:
		case WSDISPLAYIO_MODE_MAPPED:
		case WSDISPLAYIO_MODE_DUMBFB:
			break;
		default:
			return EINVAL;
		}
		sc->sc_wsmode = new_mode;
		if (new_mode == WSDISPLAYIO_MODE_EMUL && vd->active != NULL)
			vcons_redraw_screen(vd->active);
		return 0;

	default:
		return EPASSTHROUGH;
	}
}

static paddr_t
warpgfx_mmap(void *v, void *vs, off_t offset, int prot)
{
	struct vcons_data *vd = v;
	struct warpgfx_softc *sc = vd->cookie;

	if (offset < 0 || (size_t)offset >= sc->sc_fbsize)
		return -1;

	return bus_space_mmap(sc->sc_fbt, sc->sc_fbpa, offset, prot,
	    BUS_SPACE_MAP_LINEAR);
}

static int
warpgfx_get_fbinfo(struct warpgfx_softc *sc,
    struct wsdisplayio_fbinfo *fbi)
{
	memset(fbi, 0, sizeof(*fbi));
	fbi->fbi_flags = 0;
	fbi->fbi_fboffset = 0;
	/* Expose the usable aperture so wsfb EXA can allocate off-screen rows. */
	fbi->fbi_fbsize = sc->sc_fbsize;
	fbi->fbi_width = sc->sc_width;
	fbi->fbi_height = sc->sc_height;
	fbi->fbi_stride = sc->sc_stride;
	fbi->fbi_bitsperpixel = sc->sc_depth;
	fbi->fbi_pixeltype = WSFB_RGB;

	fbi->fbi_subtype.fbi_rgbmasks.alpha_offset = 0;
	fbi->fbi_subtype.fbi_rgbmasks.red_offset = 11;
	fbi->fbi_subtype.fbi_rgbmasks.green_offset = 5;
	fbi->fbi_subtype.fbi_rgbmasks.blue_offset = 0;
	fbi->fbi_subtype.fbi_rgbmasks.alpha_size = 0;
	fbi->fbi_subtype.fbi_rgbmasks.red_size = 5;
	fbi->fbi_subtype.fbi_rgbmasks.green_size = 6;
	fbi->fbi_subtype.fbi_rgbmasks.blue_size = 5;

	return 0;
}

void
warpgfxcnprobe(struct consdev *cd)
{
#ifdef WARPGFX_CONSOLE
	cd->cn_pri = warpgfx_exists ? CN_INTERNAL : CN_DEAD;
#else
	cd->cn_pri = CN_DEAD;
#endif
	cd->cn_dev = NODEV;
}

void
warpgfxcninit(struct consdev *cd)
{
#if defined(WARPGFX_CONSOLE) && NKBD > 0
	if (warpgfx_exists)
		kbd_cnattach();
#endif
}

void
warpgfxcnpollc(dev_t dev, int on)
{
}

void
warpgfxcnputc(dev_t dev, int ch)
{
}

int
warpgfxcngetc(dev_t dev)
{
	return 0;
}
