#!/bin/sh
# Shared upstream pins and managed paths. This file is sourced by other scripts.
SRC_URL='https://github.com/NetBSD/src.git'
SRC_BASE='33e354d16e88e297574c1a48a70a0111a25f0232'
XSRC_URL='https://github.com/NetBSD/xsrc.git'
XSRC_BASE='980d69e3df4433b768bffdc4c42ad3c1053692e6'

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
