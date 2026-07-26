#!/usr/bin/env python3
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from OpenAI GPT-5.6-Sol.
"""Scale PC Face's Oldschool VGA 8x16 CP437 bitmap to a 24x40 WSF.

The source glyphs remain in CP437 byte order, but the output deliberately uses
WSDISPLAY_FONTENC_ISO.  NetBSD's vt100 emulator first maps bytes 0x80-0xff to
U+0080-U+00ff; ISO wsfont encoding then selects the same-numbered glyph slot.
Marking this raw-BBS font as IBM would incorrectly remap those Unicode values.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

from generate_scaled_wsf import L2R, WsFont, read_wsf, scale_font, write_wsf

SOURCE_SHA256 = "f8c59bfc39e52dae72d04406654230d5d4d1a343554bdddfbe11a137d0154cc7"
SOURCE_WIDTH = 8
SOURCE_HEIGHT = 16
SOURCE_GLYPHS = 256
SOURCE_STRIDE = 1
WSDISPLAY_FONTENC_ISO = 0
ROW_RE = re.compile(
    r"^  \[((?:0x[0-9a-f]{2}(?:, )?){16})\], // .* \((\d+)\)$",
    re.MULTILINE,
)


def read_pcface_fontlist(path: Path) -> bytes:
    text_bytes = path.read_bytes()
    digest = hashlib.sha256(text_bytes).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError(
            f"{path}: SHA-256 {digest} does not match expected {SOURCE_SHA256}"
        )

    glyphs: list[bytes] = []
    text = text_bytes.decode("utf-8")
    for match in ROW_RE.finditer(text):
        index = int(match.group(2))
        if index != len(glyphs):
            raise ValueError(f"{path}: glyph index {index} appears at {len(glyphs)}")
        rows = bytes(int(value, 16) for value in re.findall(r"0x([0-9a-f]{2})", match.group(1)))
        if len(rows) != SOURCE_HEIGHT:
            raise ValueError(f"{path}: glyph {index} has {len(rows)} rows")
        glyphs.append(rows)

    if len(glyphs) != SOURCE_GLYPHS:
        raise ValueError(f"{path}: found {len(glyphs)} glyphs, expected {SOURCE_GLYPHS}")
    raw = b"".join(glyphs)
    if len(raw) != SOURCE_GLYPHS * SOURCE_HEIGHT * SOURCE_STRIDE:
        raise ValueError(f"{path}: extracted bitmap has unexpected size {len(raw)}")

    # Guard the CP437 line/block positions most important to ANSI/BBS artwork.
    expected = {
        0xB3: bytes([0x18] * 16),
        0xC4: bytes([0x00] * 7 + [0xFF] + [0x00] * 8),
        0xDB: bytes([0xFF] * 16),
        0xDC: bytes([0x00] * 7 + [0xFF] * 9),
        0xDF: bytes([0xFF] * 7 + [0x00] * 9),
    }
    for index, bitmap in expected.items():
        actual = raw[index * SOURCE_HEIGHT : (index + 1) * SOURCE_HEIGHT]
        if actual != bitmap:
            raise ValueError(f"{path}: CP437 glyph 0x{index:02x} is not the expected VGA bitmap")
    return raw


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="pinned PC Face fontlist.js")
    parser.add_argument("output", type=Path, help="output WSF font")
    parser.add_argument(
        "--name",
        default="WarpConsole-VGA-CP437-Raw-24x40",
        help="embedded WSF font name",
    )
    args = parser.parse_args()

    source_path = args.source.resolve()
    output_path = args.output.resolve()
    if source_path == output_path:
        parser.error("source and output paths must be different")

    raw = read_pcface_fontlist(source_path)
    source = WsFont(
        name="PCFace-Oldschool-VGA-8x16-CP437-Raw",
        firstchar=0,
        numchars=SOURCE_GLYPHS,
        encoding=WSDISPLAY_FONTENC_ISO,
        width=SOURCE_WIDTH,
        height=SOURCE_HEIGHT,
        stride=SOURCE_STRIDE,
        bitorder=L2R,
        byteorder=L2R,
        data=raw,
    )
    output = scale_font(source, 24, 40, args.name)
    write_wsf(output, output_path)

    checked = read_wsf(output_path)
    if checked != output:
        raise RuntimeError("output did not round-trip through the WSF parser")
    print(
        f"Oldschool VGA 8x16 CP437 raw -> {checked.name} 24x40 ISO/direct, "
        f"{checked.numchars} glyphs, stride {checked.stride}, "
        f"{output_path.stat().st_size} bytes"
    )


if __name__ == "__main__":
    main()
