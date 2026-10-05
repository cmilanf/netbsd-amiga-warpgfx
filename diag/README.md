# WarpGFX diagnostic tools

Small NetBSD/amiga programs for inspecting and exercising the CS-Lab Warp GFX
display hardware from user space. They were written to investigate the
1920x1080 problem seen with Warp firmware 2296, described in the top-level
[README](../README.md#known-issues), and are useful whenever the WarpGFX
console or X display misbehaves: they show what the hardware is actually doing,
independently of what the monitor shows.

Prebuilt binaries are included in every release archive under `diag/`. They are
ordinary NetBSD/m68k userland programs and do not depend on the CPU or video
mode of the kernel in the same archive.

## Tools

| Tool | Access | Purpose |
| ---- | ------ | ------- |
| `warpregs` | read-only | Dump the display registers and decode the programmed mode: output source, pixel format, sync polarity, active/total timing, pitch, pixel clock and its ready flag, expected refresh rate, sprite and blitter state. `-r` prints only the dump. |
| `warpvsync [SECONDS]` | read-only | Measure the real vertical refresh rate by counting vertical-blank flag edges (default 3 s). |
| `warpclkmon [SECONDS]` | read-only | Sample the pixel-clock status continuously (default 10 s) and report any loss of the ready flag. |
| `warpreg OFFSET [VALUE]` | read, or write | Read one register; with `VALUE` write it and read it back. `-s`/`-c` set or clear bits. |
| `warpmode MODE [COLOR16]` | writes | Program a complete display mode with the kernel driver's register values, optionally filling the screen with one 16-bit colour. `-l` lists modes; `-o` uses the `csgfx.card` 22.96 register order. |
| `warpredraw [DEVICE]` | console ioctl | Make the driver redraw the active text console (default `/dev/ttyE0`) after `warpmode` changed the screen. Not while X is running. |
| `warptest-modes.sh` | writes | Cycle through every mode, each with its own colour, so you can note which ones the monitor accepts. |
| `warptest-1080.sh` | writes | Compare 1920x1080 at 30, 50, and 60 Hz on the 74.25 and 148.5 MHz clocks, with both register orders, against a 1280x720 baseline. |

`warpmode -l` lists the available modes: `native` (the native Amiga video
passthrough the Warp shows when RTG is off), `480`, `600`, `720`, `768`, `1024`,
`1080`, and the test modes `1080p30` (1080p60 timing on the 74.25 MHz clock) and
`1080p50`.

Both test scripts hold each step for `HOLD` seconds, log a timestamp and the
measured refresh rate for every step, and restore the kernel's mode and redraw
the console when they finish or are interrupted:

```sh
HOLD=30 CYCLES=2 ./warptest-modes.sh | tee /tmp/warptest-modes.log
./warptest-1080.sh | tee /tmp/warptest-1080.log
```

| Script | Step colours |
| ------ | ------------ |
| `warptest-modes.sh` | native video (Amiga picture), red 1280x1024, green 1280x720, blue 1024x768, yellow 800x600, white 640x480, magenta 1920x1080 |
| `warptest-1080.sh` | green 1280x720 baseline, cyan 1080p30, white 1080p60 (`csgfx.card` order), orange 1080p50, magenta 1080p60 (driver order) |

## Access and safety

All tools need root, because they map `/dev/mem`. The addresses come from the
kernel's Zorro attach messages (`/var/run/dmesg.boot`, then `dmesg`): product
`5120/101` for the control registers and `5120/100` for the framebuffer.
`WARPGFX_REG_PA` and `WARPGFX_FB_PA` override them.

Only the 4 KiB display block of the control aperture is ever mapped. The Warp
communication mailbox at offset `0x1000` and above, which AmigaOS
`cswarp.library` uses to talk to the Warp, is out of reach of every tool, and
`warpreg` rejects offsets outside the block.

The read-only tools work on any kernel. Anything that writes registers needs
`kern.securelevel` 0 or lower; NetBSD normally runs at 1, which makes
`/dev/mem` read-only. On NetBSD 11 setting `securelevel=-1` in `/etc/rc.conf`
does not help: `/etc/rc.d/securelevel` refuses to lower the level and `init`
then raises 0 to 1. Use a test kernel built with `options INSECURE` instead:

```sh
./scripts/build-netbsd-amiga.sh --only-kernel --cpu 68060 \
  --warpgfx console,accel,mode=720,debug,insecure \
  --output output/insecure-68060-720
```

Boot that kernel only while testing and keep a normal kernel as the default.
While it runs, root can write any physical memory, so do not use it on a
networked system you do not control.

Register writes take effect immediately, and a wrong value can blank the
display until the next mode change or reboot. Keep a way to reach the machine
that does not depend on the Warp output (SSH, a serial console, or the native
Amiga video).

Timing measurements rely on the Amiga's system clock, so expect a small
deviation from the nominal rate (59.97 Hz is typical for 1080p60).

## Build

The release build (`scripts/build-netbsd-amiga.sh`) cross-compiles the tools
with the NetBSD/amiga toolchain whenever its destination tree is populated and
puts them under `<output>/diag/`. To build them manually on a NetBSD host from
such a workspace:

```sh
WS=$HOME/netbsd-amiga-warpgfx-build
make -C diag CC="$WS/tools-amiga/bin/m68k--netbsdelf-gcc --sysroot=$WS/obj-amiga/destdir.amiga"
```

To build natively on the Amiga, with the NetBSD `comp` set installed:

```sh
cd diag
make
```

Install by copying the six binaries and the three `warptest-*.sh` files into one
directory, for example `/usr/local/libexec/warpgfx-diag`. The scripts find the
binaries in their own directory.

## Example: firmware 2296 at 1080p

On the author's Amiga 1200 with firmware 2296, the monitor reported "out of
range" at 1920x1080 although the kernel attached normally. The tools showed:

```text
# ./warpregs
...
output:   Warp framebuffer, 16-bit pixels, sync +h +v
timing:   1920x1080 active, 2200x1125 total
clock:    index 5 = 148.500 MHz (csgfx.card 22.96 table), ready
refresh:  60.00 Hz expected (measure with warpvsync)
# ./warpvsync
vertical rate 59.974 Hz
# ./warpclkmon
10.0 s, 19714560 samples, ready bit clear 0 times, 0 value changes
```

So the Warp reported a correct, stable 1080p60 signal internally.
`warptest-1080.sh` then showed that every 74.25 MHz mode, including 1920x1080 at
30 Hz, held on the monitor, while both 148.5 MHz modes dropped within a second
whatever the register order. AmigaOS on the same firmware did not display
1920x1080 either. The problem therefore appears with the 148.5 MHz pixel clock
rather than with the register values NetBSD programs. Which part of the chain
is involved is still open: a later boot of the same kernel did show a
flickering picture. Results from other setups are welcome; see the top-level
[README](../README.md#known-issues).

## License

BSD 2-Clause; see [LICENSE.md](../LICENSE.md). Developed with the assistance
of Kiro and Anthropic Claude Opus 5.5.
