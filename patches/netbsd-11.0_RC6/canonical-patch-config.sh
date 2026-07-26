#!/bin/sh
# Shared upstream pins and managed paths. This file is sourced by other scripts.
SRC_URL='https://github.com/NetBSD/src.git'
SRC_BASE='5f3f31427306f722c40a286d23b324c2b4bddf6f'
XSRC_URL='https://github.com/NetBSD/xsrc.git'
XSRC_BASE='6ae477271c420cdacae3c18ea6fcf41cc6b9c67d'

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
