#!/bin/sh
# Shared upstream pins and managed paths. This file is sourced by other scripts.
SRC_URL='https://github.com/NetBSD/src.git'
SRC_BASE='f66621237dc60126bd8a972b6064639892b344b7'
XSRC_URL='https://github.com/NetBSD/xsrc.git'
XSRC_BASE='f18202c408fbf3cbd9cd4f9bea7281a789187e66'

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
