# Optional WarpGFX wscons fonts

This bonus bundle provides readable large fonts for a 1920x1080 WarpGFX
console. It is optional userland content: it does not alter the kernel/Xorg
overlay, generated patches, or release kernels.

The two promoted configurations were validated on NetBSD/amiga with WarpGFX:

| Artifact | WSF metadata | Intended screen | Result |
| --- | --- | --- | --- |
| [`WarpConsole-24x40.wsf`](artifacts/WarpConsole-24x40.wsf) | ISO-8859-1, 24x40 | `80x27` | Exact 1920x1080 coverage for general consoles |
| [`WarpConsole-VGA-CP437-Raw-24x40.wsf`](artifacts/WarpConsole-VGA-CP437-Raw-24x40.wsf) | ISO/direct, 24x40 CP437 slots | `80x25` | Classic VGA ANSI/BBS console |

The ISO console uses the WarpGFX driver's named `80x27` screen type:

```text
80 * 24 = 1920
27 * 40 = 1080
```

The VGA font has all 256 classic CP437 glyphs in their original byte slots.
Live testing visually confirmed IBM ANSI/BBS artwork, including line and block
characters.

## Why the CP437 font says ISO/direct

This is intentional. NetBSD's `wsemul_vt100` interprets bytes `0x80`-`0xff` as
the same-numbered Latin-1 Unicode values before font mapping. With an
IBM-encoded wsfont, raw BBS byte `0xb3` becomes `U+00B3` and is remapped instead
of selecting CP437 slot `0xb3` (vertical line).

The dedicated raw-BBS WSF therefore carries encoding value 0
(`WSDISPLAY_FONTENC_ISO`). For characters below `U+0100`, NetBSD's ISO wsfont
path returns the low byte directly, preserving raw CP437 slot selection. The
font's glyph repertoire remains CP437; the metadata describes the required
NetBSD input path.

## Install

Run as root on the NetBSD/amiga host. Installation and normal use require
only `/bin/sh`; Python is not required and no Python program is executed:

```sh
cd extras/wscons-fonts
./install.sh
```

The installer copies the two WSF files to `/usr/local/share/wscons/fonts` and
the complete reproducibility bundle to
`/usr/local/share/doc/warpgfx-wscons-fonts`. It is idempotent when existing
files are identical and refuses to replace a different file unless `--force`
is explicit. It never edits `/etc/wscons.conf` or `/etc/ttys`.

Preview or stage an installation without root access:

```sh
./install.sh --dry-run
./install.sh --destdir /tmp/warpgfx-font-stage
# Equivalent environment form:
DESTDIR=/tmp/warpgfx-font-stage ./install.sh
```

Use `--prefix /absolute/path` to override `/usr/local`. Because wscons does not
expand installer variables, replace `/usr/local` in the installed
`wscons.conf.example` with that same prefix; the installer prints this reminder.

## Configure wscons

Back up your configuration, then manually merge the desired directives from
[`wscons.conf.example`](wscons.conf.example):

```sh
cp -p /etc/wscons.conf /etc/wscons.conf.before-warpgfx-fonts
vi /etc/wscons.conf
```

The full example keeps ttyE0 unchanged as a boot/recovery console, creates
E1-E3 as ISO `80x27`, and creates E4 as a VGA raw-CP437 `80x25` console. It has
no E5 entry. `/etc/ttys` login policy is deliberately outside this example;
enable only the gettys appropriate for your system.

Ordering matters:

1. load the ISO font;
2. create E1-E3 as `80x27` and E4 as `80x25`;
3. load the raw-CP437 VGA font;
4. explicitly assign the ISO font to E1-E3 and VGA font to E4.

A safe parser-only preview on NetBSD is:

```sh
(sed '$d' /etc/rc.d/wscons; \
  echo 'wscons_start -n -f /etc/wscons.conf') | /bin/sh
```

Do not use `/etc/rc.d/wscons start -n` for this check: the rc wrapper does not
reliably pass the dry-run argument through to `wscons_start`. Do not live-switch
a default-geometry screen to a 24x40 font; create the fixed-geometry screen
first. Keep ttyE0 and a known-good kernel/configuration available as recovery
paths.

## Optional maintainer validation and artifact reproduction

This is not part of installation and should normally be run on a modern build
host, not on the Amiga. The generators and validation suite require Python 3.10
or newer and no third-party modules. Select the available command first:

```sh
PYTHON=python3

"$PYTHON" ./generate_scaled_wsf.py \
  sources/ter-132n.wsf \
  /tmp/WarpConsole-24x40.wsf \
  --width 24 --height 40 \
  --name WarpConsole-24x40-ISO8859-1

"$PYTHON" ./generate_vga_cp437_wsf.py \
  sources/PCFace-Oldschool-VGA-8x16-fontlist.js \
  /tmp/WarpConsole-VGA-CP437-Raw-24x40.wsf

cmp /tmp/WarpConsole-24x40.wsf artifacts/WarpConsole-24x40.wsf
cmp /tmp/WarpConsole-VGA-CP437-Raw-24x40.wsf \
  artifacts/WarpConsole-VGA-CP437-Raw-24x40.wsf
```

Both generators use pixel-centred nearest-neighbour scaling, a four-byte row
stride required by generic rasops for 24-pixel glyphs, atomic output writes,
and completed-WSF reparsing. The VGA generator additionally pins the exact
source SHA-256 and rejects altered input.

Run the complete validation suite with:

```sh
"$PYTHON" ./validate.py
```

It verifies source/artifact hashes and metadata, critical CP437 slots, every
one of the 491,520 scaled pixels, all 20,480 padding bytes, byte-identical
regeneration, and corrupted VGA source rejection. See [`SHA256.txt`](SHA256.txt)
for the pinned manifest.

## Licensing and provenance

Licenses are scoped per component; adding this optional directory does not
change the BSD-2-Clause license of the WarpGFX driver and tooling.

- `generate_scaled_wsf.py`, `generate_vga_cp437_wsf.py`, `validate.py`, and
  `install.sh` are new WarpGFX project code under the repository's BSD
  2-Clause license.
- `sources/ter-132n.wsf` and `artifacts/WarpConsole-24x40.wsf` are under the SIL
  Open Font License 1.1. See
  [`TERMINUS-FONT-NOTICE.md`](licenses/TERMINUS-FONT-NOTICE.md) and
  [`OFL-1.1.txt`](licenses/OFL-1.1.txt).
- `sources/PCFace-Oldschool-VGA-8x16-fontlist.js` and
  `artifacts/WarpConsole-VGA-CP437-Raw-24x40.wsf` are distributed under CC
  BY-SA 4.0. See
  [`OLDSCHOOL-VGA-FONT-NOTICE.md`](licenses/OLDSCHOOL-VGA-FONT-NOTICE.md) and
  [`CC-BY-SA-4.0.txt`](licenses/CC-BY-SA-4.0.txt).

The VGA font is a faithful Oldschool PC Fonts reproduction, not an IBM-supplied
artifact. No endorsement by IBM or any upstream font author is implied.
