#!/bin/sh
# Shared upstream pins and managed paths. This file is sourced by other scripts.
SRC_URL='https://github.com/NetBSD/src.git'
SRC_BASE='c4432964a2fc5fc62bd8f36699e5798c45cd569b'
XSRC_URL='https://github.com/NetBSD/xsrc.git'
XSRC_BASE='b8a0c79d92d984f132704159c17dc18ee9515e3c'

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
