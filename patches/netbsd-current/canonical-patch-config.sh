#!/bin/sh
# Shared upstream pins and managed paths. This file is sourced by other scripts.
SRC_URL='https://github.com/NetBSD/src.git'
SRC_BASE='bd9f26305380f03b3821f55381448a82827d6749'
XSRC_URL='https://github.com/NetBSD/xsrc.git'
XSRC_BASE='e32b53118bd84cc2f5b7986ea65525f9f1213ca7'

SRC_PATHS='external/mit/xorg/server/drivers/xf86-video-wsfb/Makefile
sys/arch/amiga/amiga/conf.c
sys/arch/amiga/conf/WSCONS
sys/arch/amiga/conf/files.amiga
sys/arch/amiga/dev/warpgfx.c
sys/arch/amiga/dev/warpgfxreg.h
sys/arch/amiga/dev/zbus.c'

XSRC_PATHS='external/mit/xf86-video-wsfb/dist/man/wsfb.man
external/mit/xf86-video-wsfb/dist/src/wsfb.h
external/mit/xf86-video-wsfb/dist/src/wsfb_driver.c
external/mit/xf86-video-wsfb/dist/src/wsfb_exa.c'
