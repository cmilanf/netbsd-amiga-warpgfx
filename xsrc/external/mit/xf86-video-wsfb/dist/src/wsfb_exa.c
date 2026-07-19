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

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>

#include "xorg-server.h"
#include "xf86.h"
#include "wsfb.h"
#include "exa.h"

#ifdef HAVE_WSFB_EXA

static Bool
WsfbEXAFullPlanemask(PixmapPtr pPixmap, Pixel planemask)
{
	Pixel mask;

	if ((unsigned int)pPixmap->drawable.depth >= sizeof(Pixel) * 8)
		mask = ~(Pixel)0;
	else
		mask = ((Pixel)1 << pPixmap->drawable.depth) - 1;

	return (planemask & mask) == mask;
}

static Bool
WsfbEXAPixmapOffset(WsfbPtr fPtr, PixmapPtr pPixmap, uint32_t *y)
{
	unsigned long offset, pitch;

	/* The wsdisplay blit ABI has one fixed pitch and absolute coordinates. */
	pitch = exaGetPixmapPitch(pPixmap);
	offset = exaGetPixmapOffset(pPixmap);
	if (pitch != fPtr->fbi.fbi_stride || pitch == 0 ||
	    offset >= fPtr->fbi.fbi_fbsize || offset % pitch != 0 ||
	    offset / pitch > UINT32_MAX)
		return FALSE;

	*y = (uint32_t)(offset / pitch);
	return TRUE;
}

static void
WsfbEXADisable(ScrnInfoPtr pScrn, const char *operation)
{
	WsfbPtr fPtr = WSFBPTR(pScrn);

	if (fPtr->exa_active) {
		xf86DrvMsg(pScrn->scrnIndex, X_ERROR,
		    "wsdisplay %s blit failed: %s; disabling acceleration\n",
		    operation, strerror(errno));
	}
	fPtr->exa_active = FALSE;
}

static void
WsfbEXAWaitMarker(ScreenPtr pScreen, int marker)
{
	ScrnInfoPtr pScrn = xf86ScreenToScrn(pScreen);
	WsfbPtr fPtr = WSFBPTR(pScrn);
	struct wsdisplayio_blit blit;

	if (!fPtr->exa_active)
		return;

	memset(&blit, 0, sizeof(blit));
	blit.serial = (uint32_t)marker;
	if (ioctl(fPtr->fd, WSDISPLAYIO_WAITBLIT, &blit) == -1)
		WsfbEXADisable(pScrn, "wait");
}

static Bool
WsfbEXAPrepareSolid(PixmapPtr pPixmap, int alu, Pixel planemask, Pixel fg)
{
	ScrnInfoPtr pScrn = xf86ScreenToScrn(pPixmap->drawable.pScreen);
	WsfbPtr fPtr = WSFBPTR(pScrn);
	uint32_t y;

	if (!fPtr->exa_active || pPixmap->drawable.bitsPerPixel != 16 ||
	    alu != GXcopy || !WsfbEXAFullPlanemask(pPixmap, planemask) ||
	    !WsfbEXAPixmapOffset(fPtr, pPixmap, &y))
		return FALSE;

	fPtr->exa_fg = fg;
	return TRUE;
}

static void
WsfbEXASolid(PixmapPtr pPixmap, int x1, int y1, int x2, int y2)
{
	ScrnInfoPtr pScrn = xf86ScreenToScrn(pPixmap->drawable.pScreen);
	WsfbPtr fPtr = WSFBPTR(pScrn);
	struct wsdisplayio_blit blit;
	uint32_t y;

	if (!fPtr->exa_active)
		return;
	if (!WsfbEXAPixmapOffset(fPtr, pPixmap, &y) || x1 < 0 || y1 < 0 ||
	    x2 <= x1 || y2 <= y1 || (uint64_t)y1 + y > UINT32_MAX) {
		errno = EINVAL;
		WsfbEXADisable(pScrn, "solid");
		return;
	}

	memset(&blit, 0, sizeof(blit));
	blit.op = WSFB_BLIT_FILL;
	blit.dstx = (uint32_t)x1;
	blit.dsty = (uint32_t)y1 + y;
	blit.width = (uint32_t)(x2 - x1);
	blit.height = (uint32_t)(y2 - y1);
	blit.pen = (uint32_t)fPtr->exa_fg;
	if (ioctl(fPtr->fd, WSDISPLAYIO_DOBLIT, &blit) == -1)
		WsfbEXADisable(pScrn, "solid");
}

static void
WsfbEXADoneSolid(PixmapPtr pPixmap)
{
	(void)pPixmap;
}

static Bool
WsfbEXAPrepareCopy(PixmapPtr pSrcPixmap, PixmapPtr pDstPixmap, int xdir,
    int ydir, int alu, Pixel planemask)
{
	ScrnInfoPtr pScrn = xf86ScreenToScrn(pDstPixmap->drawable.pScreen);
	WsfbPtr fPtr = WSFBPTR(pScrn);
	uint32_t dst_y;

	(void)xdir;
	(void)ydir;

	if (!fPtr->exa_active ||
	    pSrcPixmap->drawable.bitsPerPixel != 16 ||
	    pDstPixmap->drawable.bitsPerPixel != 16 || alu != GXcopy ||
	    !WsfbEXAFullPlanemask(pDstPixmap, planemask) ||
	    !WsfbEXAPixmapOffset(fPtr, pSrcPixmap, &fPtr->exa_src_y) ||
	    !WsfbEXAPixmapOffset(fPtr, pDstPixmap, &dst_y))
		return FALSE;

	return TRUE;
}

static void
WsfbEXACopy(PixmapPtr pDstPixmap, int src_x, int src_y, int dst_x,
    int dst_y, int width, int height)
{
	ScrnInfoPtr pScrn = xf86ScreenToScrn(pDstPixmap->drawable.pScreen);
	WsfbPtr fPtr = WSFBPTR(pScrn);
	struct wsdisplayio_blit blit;
	uint32_t y;

	if (!fPtr->exa_active)
		return;
	if (!WsfbEXAPixmapOffset(fPtr, pDstPixmap, &y) || src_x < 0 ||
	    src_y < 0 || dst_x < 0 || dst_y < 0 || width <= 0 ||
	    height <= 0 || (uint64_t)src_y + fPtr->exa_src_y > UINT32_MAX ||
	    (uint64_t)dst_y + y > UINT32_MAX) {
		errno = EINVAL;
		WsfbEXADisable(pScrn, "copy");
		return;
	}

	memset(&blit, 0, sizeof(blit));
	blit.op = WSFB_BLIT_COPY;
	blit.srcx = (uint32_t)src_x;
	blit.srcy = (uint32_t)src_y + fPtr->exa_src_y;
	blit.dstx = (uint32_t)dst_x;
	blit.dsty = (uint32_t)dst_y + y;
	blit.width = (uint32_t)width;
	blit.height = (uint32_t)height;
	if (ioctl(fPtr->fd, WSDISPLAYIO_DOBLIT, &blit) == -1)
		WsfbEXADisable(pScrn, "copy");
}

static void
WsfbEXADoneCopy(PixmapPtr pDstPixmap)
{
	(void)pDstPixmap;
}

Bool
WsfbEXAInit(ScreenPtr pScreen)
{
	ScrnInfoPtr pScrn = xf86ScreenToScrn(pScreen);
	WsfbPtr fPtr = WSFBPTR(pScrn);
	ExaDriverPtr pExa;
	struct wsdisplayio_blit blit;
	size_t memory_size, visible_size;

	if (fPtr->fbi.fbi_bitsperpixel != 16 ||
	    fPtr->fbi.fbi_pixeltype != WSFB_RGB ||
	    fPtr->fbi.fbi_stride == 0 ||
	    fPtr->fbi.fbi_stride > INT_MAX ||
	    fPtr->fbi.fbi_width > INT_MAX ||
	    fPtr->fbi.fbi_fbsize > SIZE_MAX ||
	    fPtr->fbi.fbi_height > SIZE_MAX / fPtr->fbi.fbi_stride)
		return FALSE;

	memset(&blit, 0, sizeof(blit));
	if (ioctl(fPtr->fd, WSDISPLAYIO_WAITBLIT, &blit) == -1)
		return FALSE;

	memory_size = (size_t)fPtr->fbi.fbi_fbsize;
	memory_size -= memory_size % fPtr->fbi.fbi_stride;
	visible_size = (size_t)fPtr->fbi.fbi_stride *
	    fPtr->fbi.fbi_height;
	if (memory_size < visible_size ||
	    memory_size / fPtr->fbi.fbi_stride > INT_MAX)
		return FALSE;

	pExa = exaDriverAlloc();
	if (pExa == NULL)
		return FALSE;

	fPtr->pExa = pExa;
	fPtr->exa_active = TRUE;

	pExa->exa_major = EXA_VERSION_MAJOR;
	pExa->exa_minor = EXA_VERSION_MINOR;
	pExa->memoryBase = fPtr->fbstart;
	pExa->memorySize = memory_size;
	pExa->offScreenBase = visible_size;
	pExa->pixmapOffsetAlign = (int)fPtr->fbi.fbi_stride;
	pExa->pixmapPitchAlign = (int)fPtr->fbi.fbi_stride;
	pExa->flags = EXA_OFFSCREEN_PIXMAPS | EXA_MIXED_PIXMAPS;
	pExa->maxX = (int)fPtr->fbi.fbi_width;
	pExa->maxY = (int)(memory_size / fPtr->fbi.fbi_stride);

	pExa->WaitMarker = WsfbEXAWaitMarker;
	/* DOBLIT completes synchronously, so these hooks need no exaMarkSync(). */
	pExa->PrepareSolid = WsfbEXAPrepareSolid;
	pExa->Solid = WsfbEXASolid;
	pExa->DoneSolid = WsfbEXADoneSolid;
	pExa->PrepareCopy = WsfbEXAPrepareCopy;
	pExa->Copy = WsfbEXACopy;
	pExa->DoneCopy = WsfbEXADoneCopy;

	if (!exaDriverInit(pScreen, pExa)) {
		fPtr->exa_active = FALSE;
		fPtr->pExa = NULL;
		free(pExa);
		return FALSE;
	}

	return TRUE;
}

#endif /* HAVE_WSFB_EXA */
