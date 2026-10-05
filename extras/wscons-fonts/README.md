# Optional WarpGFX wscons fonts

This bonus bundle provides readable fonts that fill a WarpGFX console exactly at
640x480, 1280x720, and 1920x1080. It is optional userland content: it does not
alter the kernel/Xorg overlay, generated patches, or release kernels.

For every mode there is a general ISO-8859-1 console font and a classic VGA
raw-CP437 font for ANSI/BBS work. Pick the example configuration that matches
the `mode=` your WarpGFX kernel was built with (`sysctl hw.warpgfx.version` does
not show it; `dmesg | grep warpgfx` does):

| Kernel mode | ISO console | Screen | Raw CP437 console | Screen | Example |
| --- | --- | --- | --- | --- | --- |
| 640x480 | NetBSD's own `ter-116n.wsf` (Terminus 8x16) | `80x30`, exact | [`WarpConsole-VGA-CP437-Raw-8x16.wsf`](artifacts/WarpConsole-VGA-CP437-Raw-8x16.wsf) | `80x25`, 640x400 centred | [`wscons-640x480.conf.example`](wscons-640x480.conf.example) |
| 1280x720 | [`WarpConsole-16x30.wsf`](artifacts/WarpConsole-16x30.wsf) | `80x24`, exact | [`WarpConsole-VGA-CP437-Raw-16x28.wsf`](artifacts/WarpConsole-VGA-CP437-Raw-16x28.wsf) | `80x25`, 1280x700 centred | [`wscons-1280x720.conf.example`](wscons-1280x720.conf.example) |
| 1920x1080 | [`WarpConsole-24x40.wsf`](artifacts/WarpConsole-24x40.wsf) | `80x27`, exact | [`WarpConsole-VGA-CP437-Raw-24x40.wsf`](artifacts/WarpConsole-VGA-CP437-Raw-24x40.wsf) | `80x25`, 1920x1000 centred | [`wscons-1920x1080.conf.example`](wscons-1920x1080.conf.example) |

The exact-fit geometries work out as:

```text
 640x480:   80 *  8 =  640    30 * 16 =  480
1280x720:   80 * 16 = 1280    24 * 30 =  720
1920x1080:  80 * 24 = 1920    27 * 40 = 1080
```

The `80x24` and `80x30` screen types need WarpGFX 1.1 or newer; `80x25` and
`80x27` exist in every version. The 1920x1080 pair was validated live on
NetBSD/amiga with WarpGFX. The 1280x720 and 640x480 fonts pass the same
pixel-level validation (below) and use the same driver code path. 1920x1080 has
been unreliable with Warp firmware 2296 on the author's setup (see the top-level
README), so the releases for that firmware ship 1280x720 and 640x480 kernels.

The VGA fonts have all 256 classic CP437 glyphs in their original byte slots.
Live testing visually confirmed IBM ANSI/BBS artwork, including line and block
characters.

## Why the CP437 fonts say ISO/direct

This is intentional. NetBSD's `wsemul_vt100` interprets bytes `0x80`-`0xff` as
the same-numbered Latin-1 Unicode values before font mapping. With an
IBM-encoded wsfont, raw BBS byte `0xb3` becomes `U+00B3` and is remapped instead
of selecting CP437 slot `0xb3` (vertical line).

The dedicated raw-BBS WSF files therefore carry encoding value 0
(`WSDISPLAY_FONTENC_ISO`). For characters below `U+0100`, NetBSD's ISO wsfont
path returns the low byte directly, preserving raw CP437 slot selection. The
fonts' glyph repertoire remains CP437; the metadata describes the required
NetBSD input path.

## Install

Run as root on the NetBSD/amiga host. Installation and normal use require
only `/bin/sh`; Python is not required and no Python program is executed:

```sh
cd extras/wscons-fonts
./install.sh
```

The installer copies the five WSF files to `/usr/local/share/wscons/fonts` and
the complete reproducibility bundle, including all three example
configurations, to `/usr/local/share/doc/warpgfx-wscons-fonts`. It is
idempotent when existing files are identical and refuses to replace a different
file unless `--force` is explicit. It never edits `/etc/wscons.conf` or
`/etc/ttys`.

Preview or stage an installation without root access:

```sh
./install.sh --dry-run
./install.sh --destdir /var/tmp/warpgfx-font-stage
# Equivalent environment form:
DESTDIR=/var/tmp/warpgfx-font-stage ./install.sh
```

Use `--prefix /absolute/path` to override `/usr/local`. Because wscons does not
expand installer variables, replace `/usr/local` in the installed example with
that same prefix; the installer prints this reminder. The installer refuses
paths with symlinked components, so stage into a directory that has none.

## Configure wscons

Back up your configuration, then manually merge the desired directives from the
example for your mode:

```sh
cp -p /etc/wscons.conf /etc/wscons.conf.before-warpgfx-fonts
vi /etc/wscons.conf
```

Each example keeps ttyE0 unchanged as a boot/recovery console, creates E1-E3 as
exact-fit ISO screens, and creates E4 as a VGA raw-CP437 `80x25` console. None
has an E5 entry. `/etc/ttys` login policy is deliberately outside the examples;
enable only the gettys appropriate for your system.

Use the example that matches the kernel's mode. A font larger than its screen
type allows (for example the 24x40 fonts on a 1280x720 kernel) makes WarpGFX
1.1 shrink that screen to the largest geometry that fits. WarpGFX 1.0 panics
with an MMU fault in `vcons_eraserows` instead.

Ordering matters:

1. load the ISO font;
2. create E1-E3 with the exact-fit type and E4 as `80x25`;
3. load the raw-CP437 VGA font;
4. explicitly assign the ISO font to E1-E3 and the VGA font to E4.

A safe parser-only preview on NetBSD is:

```sh
(sed '$d' /etc/rc.d/wscons; \
  echo 'wscons_start -n -f /etc/wscons.conf') | /bin/sh
```

Do not use `/etc/rc.d/wscons start -n` for this check: the rc wrapper does not
reliably pass the dry-run argument through to `wscons_start`. Do not live-switch
a default-geometry screen to one of these fonts; create the fixed-geometry
screen first. Keep ttyE0 and a known-good kernel/configuration available as
recovery paths.

## Optional maintainer validation and artifact reproduction

This is not part of installation and should normally be run on a modern build
host, not on the Amiga. The generators and validation suite require Python 3.10
or newer and no third-party modules. Select the available command first:

```sh
PYTHON=python3

"$PYTHON" ./generate_scaled_wsf.py sources/ter-132n.wsf \
  /tmp/WarpConsole-24x40.wsf \
  --width 24 --height 40 --name WarpConsole-24x40-ISO8859-1
"$PYTHON" ./generate_scaled_wsf.py sources/ter-132n.wsf \
  /tmp/WarpConsole-16x30.wsf \
  --width 16 --height 30 --name WarpConsole-16x30-ISO8859-1

"$PYTHON" ./generate_vga_cp437_wsf.py \
  sources/PCFace-Oldschool-VGA-8x16-fontlist.js \
  /tmp/WarpConsole-VGA-CP437-Raw-24x40.wsf
"$PYTHON" ./generate_vga_cp437_wsf.py \
  sources/PCFace-Oldschool-VGA-8x16-fontlist.js \
  /tmp/WarpConsole-VGA-CP437-Raw-16x28.wsf --width 16 --height 28
"$PYTHON" ./generate_vga_cp437_wsf.py \
  sources/PCFace-Oldschool-VGA-8x16-fontlist.js \
  /tmp/WarpConsole-VGA-CP437-Raw-8x16.wsf --width 8 --height 16

for f in /tmp/WarpConsole-*.wsf; do cmp "$f" "artifacts/${f##*/}"; done
```

Both generators use pixel-centred nearest-neighbour scaling, a four-byte row
stride required by generic rasops for widths without an optimized path, atomic
output writes, and completed-WSF reparsing. The VGA generator defaults to 24x40,
names its output `WarpConsole-VGA-CP437-Raw-WIDTHxHEIGHT`, and pins the exact
source SHA-256, rejecting altered input.

Run the complete validation suite with:

```sh
"$PYTHON" ./validate.py
```

For all five fonts it verifies source and artifact hashes against
[`SHA256.txt`](SHA256.txt), metadata, critical CP437 slots, every one of the
761,856 rendered pixels, all 62,464 padding bytes, byte-identical
regeneration, and corrupted VGA source rejection.

## Licensing and provenance

Licenses are scoped per component; adding this optional directory does not
change the BSD-2-Clause license of the WarpGFX driver and tooling.

- `generate_scaled_wsf.py`, `generate_vga_cp437_wsf.py`, `validate.py`, and
  `install.sh` are new WarpGFX project code under the repository's BSD
  2-Clause license.
- `sources/ter-132n.wsf`, `artifacts/WarpConsole-24x40.wsf`, and
  `artifacts/WarpConsole-16x30.wsf` are under the SIL Open Font License 1.1.
  See [`TERMINUS-FONT-NOTICE.md`](licenses/TERMINUS-FONT-NOTICE.md) and
  [`OFL-1.1.txt`](licenses/OFL-1.1.txt). The 640x480 example uses NetBSD's own
  `ter-116n.wsf` unmodified, in place.
- `sources/PCFace-Oldschool-VGA-8x16-fontlist.js` and the three
  `artifacts/WarpConsole-VGA-CP437-Raw-*.wsf` files are distributed under CC
  BY-SA 4.0. See
  [`OLDSCHOOL-VGA-FONT-NOTICE.md`](licenses/OLDSCHOOL-VGA-FONT-NOTICE.md) and
  [`CC-BY-SA-4.0.txt`](licenses/CC-BY-SA-4.0.txt).

The VGA fonts are faithful Oldschool PC Fonts reproductions, not IBM-supplied
artifacts. No endorsement by IBM or any upstream font author is implied.
