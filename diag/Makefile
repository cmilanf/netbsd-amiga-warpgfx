# WarpGFX diagnostic tools.
#
# Native build on NetBSD/amiga:   make
# Cross build on a NetBSD host:   make CC="$TOOLDIR/bin/m68k--netbsdelf-gcc \
#                                     --sysroot=$DESTDIR"
# scripts/build-netbsd-amiga.sh does the cross build automatically.

PROGS=		warpregs warpvsync warpclkmon warpreg warpmode warpredraw
CC?=		cc
CFLAGS?=	-O2
WARNFLAGS=	-Wall -Wextra -Werror
BUILD=		${CC} ${CFLAGS} ${WARNFLAGS}

all: ${PROGS}

warpregs: warpregs.c warpdiag.h
	${BUILD} -o $@ warpregs.c

warpvsync: warpvsync.c warpdiag.h
	${BUILD} -o $@ warpvsync.c

warpclkmon: warpclkmon.c warpdiag.h
	${BUILD} -o $@ warpclkmon.c

warpreg: warpreg.c warpdiag.h
	${BUILD} -o $@ warpreg.c

warpmode: warpmode.c warpdiag.h
	${BUILD} -o $@ warpmode.c

warpredraw: warpredraw.c
	${BUILD} -o $@ warpredraw.c

clean:
	rm -f ${PROGS}

.PHONY: all clean
