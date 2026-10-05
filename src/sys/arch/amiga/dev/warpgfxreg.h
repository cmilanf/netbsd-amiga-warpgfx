/*	$NetBSD$	*/

/*-
 * Copyright (c) 2026 Carlos Milán Figueredo
 * with assistance from OpenAI gpt-5.6-sol, Kiro, and Anthropic Claude Opus 5.5
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

#ifndef _AMIGA_DEV_WARPGFXREG_H_
#define _AMIGA_DEV_WARPGFXREG_H_

/*
 * WarpGFX driver software version.
 *
 * This is the version of this driver, independent of the NetBSD base it is
 * built against and of any (unread) Warp board firmware.  It is available
 * through the read-only hw.warpgfx.version sysctl.
 */
#define WARPGFX_VERSION		"1.1"

/*
 * CS-Lab Warp GFX interface.
 *
 * These definitions were derived from the public Zorro configuration
 * interface and from observing the register accesses made by csgfx.card
 * 17.68 (Warp firmware 1768) and 22.96 (Warp firmware 2296).  Names for
 * registers whose exact hardware name is not known are intentionally
 * descriptive rather than authoritative.
 *
 * Firmware 2296 changes observed in csgfx.card 22.96:
 *  - pixel clock 0 is now 25.175 MHz (it was 31.5 MHz), so 640x480 uses
 *    standard 60 Hz timing instead of the former 75 Hz timing;
 *  - the mode register carries per-mode sync polarity in bits 0 and 1;
 *  - after a pixel-clock change the mode register commit bit is pulsed.
 * Timing, pitch, clock, and commit values for 800x600, 1280x720,
 * 1280x1024, and 1920x1080 are identical in both versions; 1024x768 gains
 * negative sync polarity.
 */

/* Zorro IDs. */
#define WARPGFX_MANID			0x1400
#define WARPGFX_PRODID_FB		100
#define WARPGFX_PRODID_REG		101
#define WARPGFX_PRODID_FLASH		102

/* Address-space sizes advertised by AutoConfig. */
#define WARPGFX_FB_APERTURE_SIZE	0x02000000U	/* 32 MiB */
#define WARPGFX_FB_USABLE_SIZE		0x01800000U	/* 24 MiB */
#define WARPGFX_REG_SIZE		0x00010000U	/* 64 KiB */

/* Supported 16-bit console modes (values used by WARPGFX_MODE). */
#define WARPGFX_MODE_480P		480
#define WARPGFX_MODE_600P		600
#define WARPGFX_MODE_720P		720
#define WARPGFX_MODE_768P		768
#define WARPGFX_MODE_1024P		1024
#define WARPGFX_MODE_1080P		1080
#define WARPGFX_DEPTH			16

/* Main display-control registers. */
#define WARPGFX_REG_FB_OFFSET		0x0000
#define WARPGFX_REG_FORMAT_PITCH	0x0004

/* 2D engine descriptor and status registers. */
#define WARPGFX_REG_BLT_SRC_ADDRESS	0x0008
#define WARPGFX_REG_BLT_DST_ADDRESS	0x000c
#define WARPGFX_REG_BLT_SRC_XY		0x0010
#define WARPGFX_REG_BLT_DST_XY		0x0014
#define WARPGFX_REG_BLT_SIZE		0x0018
#define WARPGFX_REG_BLT_COLOR		0x001c
#define WARPGFX_REG_BLT_COMMAND		0x0020
#define WARPGFX_REG_BLT_STATUS		0x0024
#define WARPGFX_REG_BLT_SRC_STRIDE	0x0028
#define WARPGFX_REG_BLT_DST_STRIDE	0x002c
#define WARPGFX_BLT_STATUS_BUSY_MASK	0x00000019U
#define WARPGFX_BLT_COMMAND_COPY_16	0x00000005U
#define WARPGFX_BLT_COMMAND_FILL_16	0x00000006U

#define WARPGFX_REG_OUTPUT_AUX		0x0030

/* Display timing bank. */
#define WARPGFX_REG_H_ACTIVE		0x0100
#define WARPGFX_REG_H_TIMING_1		0x0104
#define WARPGFX_REG_H_TIMING_2		0x0108
#define WARPGFX_REG_V_ACTIVE		0x010c
#define WARPGFX_REG_V_TIMING_1		0x0110
#define WARPGFX_REG_V_TIMING_2		0x0114
#define WARPGFX_REG_HV_TOTAL		0x0118
#define WARPGFX_REG_MODE_COMMIT		0x011c
#define WARPGFX_REG_SCALE_CONTROL	0x0128

/* WARPGFX_REG_SCALE_CONTROL bits (SetSprite and SetGC in csgfx.card). */
#define WARPGFX_SCALE_SPRITE_ENABLE	0x00000001U
#define WARPGFX_SCALE_SPRITE_DOUBLE	0x00000002U
#define WARPGFX_SCALE_FACTOR_MASK	0x0000003cU

/* Pixel-clock selector, lock status, and interrupt control. */
#define WARPGFX_REG_CLOCK_STATUS	0x0200
#define WARPGFX_REG_CLOCK_CONTROL	0x0204
#define WARPGFX_REG_INTERRUPT_STATUS	0x0208
#define WARPGFX_REG_INTERRUPT_CONTROL	0x020c
#define WARPGFX_CLOCK_SELECT_MASK	0x00000007U
#define WARPGFX_CLOCK_READY		0x00000002U

/*
 * Values csgfx.card writes to WARPGFX_REG_INTERRUPT_CONTROL from
 * SetInterrupt(): 3 enables the vertical-blank interrupt (INT2), 2 disables
 * it.  Its INT2 handler rewrites the register after seeing bit 0 of
 * WARPGFX_REG_INTERRUPT_STATUS, apparently to acknowledge the interrupt.
 */
#define WARPGFX_INTERRUPT_VBLANK_OFF	0x00000002U
#define WARPGFX_INTERRUPT_VBLANK_ON	0x00000003U

/*
 * Pixel-clock indices from the csgfx.card 22.96 clock table:
 * 0 = 25.175, 1 = 40, 2 = 65, 3 = 74.25, 4 = 108, 5 = 148.5 MHz.
 * The control value written is the index with bit 4 set.
 */
#define WARPGFX_480P_CLOCK_SELECT	0x00000000U
#define WARPGFX_480P_CLOCK_CONTROL	0x00000010U
#define WARPGFX_600P_CLOCK_SELECT	0x00000001U
#define WARPGFX_600P_CLOCK_CONTROL	0x00000011U
#define WARPGFX_720P_CLOCK_SELECT	0x00000003U
#define WARPGFX_720P_CLOCK_CONTROL	0x00000013U
#define WARPGFX_768P_CLOCK_SELECT	0x00000002U
#define WARPGFX_768P_CLOCK_CONTROL	0x00000012U
#define WARPGFX_1024P_CLOCK_SELECT	0x00000004U
#define WARPGFX_1024P_CLOCK_CONTROL	0x00000014U
#define WARPGFX_1080P_CLOCK_SELECT	0x00000005U
#define WARPGFX_1080P_CLOCK_CONTROL	0x00000015U

/* Other register banks. */
#define WARPGFX_REG_PALETTE_BASE	0x0800
#define WARPGFX_REG_COMMAND		0x0c00
#define WARPGFX_REG_COMMAND_RESET	0x0c04

/*
 * 640x480p60 (25.175 MHz, 800x525 total), 16-bit big-endian R5G6B5.
 * Firmware 2296 runs pixel clock 0 at 25.175 MHz; csgfx.card 17.68 used
 * 640x480 at about 75 Hz on a 31.5 MHz clock 0.
 */
#define WARPGFX_480P_FORMAT_PITCH	0x14078050U
#define WARPGFX_480P_H_ACTIVE		0x00000280U
#define WARPGFX_480P_H_TIMING_1		0x00280320U
#define WARPGFX_480P_H_TIMING_2		0x002902f0U
#define WARPGFX_480P_V_ACTIVE		0x000001e0U
#define WARPGFX_480P_V_TIMING_1		0x001e020dU
#define WARPGFX_480P_V_TIMING_2		0x001ea1ecU
#define WARPGFX_480P_HV_TOTAL		0x0020d320U
#define WARPGFX_480P_SYNC \
	(WARPGFX_MODE_SYNC_NEG_H | WARPGFX_MODE_SYNC_NEG_V)

/* 800x600, 16-bit big-endian R5G6B5 mode values. */
#define WARPGFX_600P_FORMAT_PITCH	0x19096064U
#define WARPGFX_600P_H_ACTIVE		0x00000320U
#define WARPGFX_600P_H_TIMING_1		0x00320420U
#define WARPGFX_600P_H_TIMING_2		0x003483c8U
#define WARPGFX_600P_V_ACTIVE		0x00000258U
#define WARPGFX_600P_V_TIMING_1		0x00258274U
#define WARPGFX_600P_V_TIMING_2		0x0025925dU
#define WARPGFX_600P_HV_TOTAL		0x00274420U
#define WARPGFX_600P_SYNC		0x00000000U

/* 1280x720, 16-bit big-endian R5G6B5 mode values. */
#define WARPGFX_720P_FORMAT_PITCH	0x280b40a0U
#define WARPGFX_720P_H_ACTIVE		0x00000500U
#define WARPGFX_720P_H_TIMING_1		0x00500672U
#define WARPGFX_720P_H_TIMING_2		0x0056e596U
#define WARPGFX_720P_V_ACTIVE		0x000002d0U
#define WARPGFX_720P_V_TIMING_1		0x002d02eeU
#define WARPGFX_720P_V_TIMING_2		0x002d52daU
#define WARPGFX_720P_HV_TOTAL		0x002ee672U
#define WARPGFX_720P_SYNC		0x00000000U

/* 1024x768, 16-bit big-endian R5G6B5 mode values. */
#define WARPGFX_768P_FORMAT_PITCH	0x200c0080U
#define WARPGFX_768P_H_ACTIVE		0x00000400U
#define WARPGFX_768P_H_TIMING_1		0x00400540U
#define WARPGFX_768P_H_TIMING_2		0x004184a0U
#define WARPGFX_768P_V_ACTIVE		0x00000300U
#define WARPGFX_768P_V_TIMING_1		0x00300326U
#define WARPGFX_768P_V_TIMING_2		0x00303309U
#define WARPGFX_768P_HV_TOTAL		0x00326540U
#define WARPGFX_768P_SYNC \
	(WARPGFX_MODE_SYNC_NEG_H | WARPGFX_MODE_SYNC_NEG_V)

/* 1280x1024, 16-bit big-endian R5G6B5 mode values. */
#define WARPGFX_1024P_FORMAT_PITCH	0x281000a0U
#define WARPGFX_1024P_H_ACTIVE		0x00000500U
#define WARPGFX_1024P_H_TIMING_1	0x00500698U
#define WARPGFX_1024P_H_TIMING_2	0x005305a0U
#define WARPGFX_1024P_V_ACTIVE		0x00000400U
#define WARPGFX_1024P_V_TIMING_1	0x0040042aU
#define WARPGFX_1024P_V_TIMING_2	0x00401404U
#define WARPGFX_1024P_HV_TOTAL		0x0042a698U
#define WARPGFX_1024P_SYNC		0x00000000U

/* 1920x1080p60, 16-bit big-endian R5G6B5 mode values. */
#define WARPGFX_1080P_FORMAT_PITCH	0x3c10e0f0U
#define WARPGFX_1080P_H_ACTIVE		0x00000780U
#define WARPGFX_1080P_H_TIMING_1	0x00780898U
#define WARPGFX_1080P_H_TIMING_2	0x007d8804U
#define WARPGFX_1080P_V_ACTIVE		0x00000438U
#define WARPGFX_1080P_V_TIMING_1	0x00438465U
#define WARPGFX_1080P_V_TIMING_2	0x0043c441U
#define WARPGFX_1080P_HV_TOTAL		0x00465898U
#define WARPGFX_1080P_SYNC		0x00000000U

/*
 * WARPGFX_REG_MODE_COMMIT bits.
 *
 * Bit 7 selects the Warp framebuffer instead of the external/native input.
 * Bit 3 selects 16-bit pixels (bit 4 would select 32-bit).  Writing the
 * value with bit 2 set and then clear commits the programmed mode; firmware
 * 2296 csgfx.card also issues that pulse after every pixel-clock change.
 * Bits 0 and 1 are new in csgfx.card 22.96: it sets both for 640x480 and
 * 1024x768, only bit 1 for 640x400, and neither for 800x600, 1280x720,
 * 1280x1024, or 1920x1080, matching negative vertical and horizontal sync
 * polarity of the standard VESA/CEA timings.
 */
#define WARPGFX_MODE_FB_SELECT		0x00000080U
#define WARPGFX_MODE_FORMAT_16		0x00000008U
#define WARPGFX_MODE_COMMIT_PULSE	0x00000004U
#define WARPGFX_MODE_SYNC_NEG_H		0x00000002U
#define WARPGFX_MODE_SYNC_NEG_V		0x00000001U
#define WARPGFX_MODE_SYNC_MASK \
	(WARPGFX_MODE_SYNC_NEG_H | WARPGFX_MODE_SYNC_NEG_V)

#endif /* _AMIGA_DEV_WARPGFXREG_H_ */
