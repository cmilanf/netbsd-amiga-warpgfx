/*
 * Copyright (c) 2026, Carlos Milán Figueredo
 * SPDX-License-Identifier: BSD-2-Clause
 * Developed with assistance from Kiro and Anthropic Claude Opus 5.5.
 *
 * warpredraw: ask the console driver to redraw its active text screen.
 *
 *   warpredraw [DEVICE]
 *
 * Switches DEVICE (default /dev/ttyE0) to mapped mode and back to
 * emulation mode, the same transition X performs on exit.  The WarpGFX
 * driver redraws the active virtual console when it re-enters emulation
 * mode, which restores the text after warpmode filled the framebuffer.
 * Do not run it while X is using the display.  Needs root.
 */

#include <sys/ioctl.h>

#include <dev/wscons/wsconsio.h>

#include <err.h>
#include <fcntl.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	const char *dev = "/dev/ttyE0";
	u_int mode;
	int fd;

	if (argc == 2)
		dev = argv[1];
	else if (argc != 1)
		errx(2, "usage: warpredraw [DEVICE]");

	if ((fd = open(dev, O_RDWR)) == -1)
		err(1, "%s", dev);
	if (ioctl(fd, WSDISPLAYIO_GMODE, &mode) == -1)
		err(1, "%s: WSDISPLAYIO_GMODE", dev);
	if (mode != WSDISPLAYIO_MODE_EMUL)
		errx(1, "%s is not in text mode (is X running?)", dev);
	mode = WSDISPLAYIO_MODE_MAPPED;
	if (ioctl(fd, WSDISPLAYIO_SMODE, &mode) == -1)
		err(1, "%s: WSDISPLAYIO_SMODE mapped", dev);
	mode = WSDISPLAYIO_MODE_EMUL;
	if (ioctl(fd, WSDISPLAYIO_SMODE, &mode) == -1)
		err(1, "%s: WSDISPLAYIO_SMODE emul", dev);
	close(fd);
	return 0;
}
