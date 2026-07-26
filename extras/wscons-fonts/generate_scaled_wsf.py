#!/usr/bin/env python3
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from OpenAI GPT-5.6-Sol.
"""Scale a monochrome NetBSD WSF font with nearest-neighbour sampling.

The output uses a four-byte bitmap stride. NetBSD's generic rasops renderer
reads a big-endian 32-bit bitmap word for each glyph row, so this is required
for non-optimized widths such as 24 pixels.
"""

from __future__ import annotations

import argparse
import os
import struct
import tempfile
from dataclasses import dataclass
from pathlib import Path

MAGIC = b"WSFT"
NAME_SIZE = 64
HEADER = struct.Struct("<8I")
HEADER_SIZE = len(MAGIC) + NAME_SIZE + HEADER.size
L2R = 1
VALID_ORDERS = {0, 1, 2}


@dataclass(frozen=True)
class WsFont:
    name: str
    firstchar: int
    numchars: int
    encoding: int
    width: int
    height: int
    stride: int
    bitorder: int
    byteorder: int
    data: bytes


def read_wsf(path: Path) -> WsFont:
    raw = path.read_bytes()
    if len(raw) < HEADER_SIZE or raw[:4] != MAGIC:
        raise ValueError(f"{path}: not a WSF font")

    name_raw = raw[4 : 4 + NAME_SIZE]
    name = name_raw.split(b"\0", 1)[0].decode("ascii")
    fields = HEADER.unpack_from(raw, 4 + NAME_SIZE)
    firstchar, numchars, encoding, width, height, stride, bitorder, byteorder = fields

    if numchars < 1:
        raise ValueError(f"{path}: font has no glyphs")
    if width < 1 or height < 1:
        raise ValueError(f"{path}: font dimensions must be positive")
    minimum_stride = (width + 7) // 8
    if stride < minimum_stride:
        raise ValueError(
            f"{path}: stride {stride} cannot hold {width} bitmap pixels"
        )
    if stride >= width:
        raise ValueError(f"{path}: alpha font layouts are not supported")
    if bitorder not in VALID_ORDERS or byteorder not in VALID_ORDERS:
        raise ValueError(f"{path}: invalid bit or byte order")

    expected = HEADER_SIZE + numchars * height * stride
    if len(raw) != expected:
        raise ValueError(f"{path}: size {len(raw)} != expected {expected}")

    return WsFont(
        name,
        firstchar,
        numchars,
        encoding,
        width,
        height,
        stride,
        bitorder,
        byteorder,
        raw[HEADER_SIZE:],
    )


def glyph_pixel(font: WsFont, glyph: int, x: int, y: int) -> bool:
    row = (glyph * font.height + y) * font.stride
    byte = font.data[row + x // 8]
    if font.bitorder == L2R:
        return bool(byte & (0x80 >> (x % 8)))
    return bool(byte & (1 << (x % 8)))


def scale_font(source: WsFont, width: int, height: int, name: str) -> WsFont:
    if source.bitorder != L2R or source.byteorder != L2R:
        raise ValueError("only L2R bit- and byte-ordered source fonts are supported")
    if not 4 <= width <= 32:
        raise ValueError("rasops bitmap font width must be between 4 and 32 pixels")
    if height < 1:
        raise ValueError("font height must be positive")
    if len(name.encode("ascii")) >= NAME_SIZE:
        raise ValueError("WSF font name must be at most 63 ASCII bytes")

    # The generic rasops putchar path fetches one 32-bit word per bitmap row.
    stride = 4
    output = bytearray(source.numchars * height * stride)

    for glyph in range(source.numchars):
        for dy in range(height):
            # Pixel-centre nearest-neighbour mapping avoids a one-sided bias.
            sy = min(source.height - 1, ((2 * dy + 1) * source.height) // (2 * height))
            row = (glyph * height + dy) * stride
            for dx in range(width):
                sx = min(source.width - 1, ((2 * dx + 1) * source.width) // (2 * width))
                if glyph_pixel(source, glyph, sx, sy):
                    output[row + dx // 8] |= 0x80 >> (dx % 8)

    return WsFont(
        name,
        source.firstchar,
        source.numchars,
        source.encoding,
        width,
        height,
        stride,
        source.bitorder,
        source.byteorder,
        bytes(output),
    )


def write_wsf(font: WsFont, path: Path) -> None:
    encoded_name = font.name.encode("ascii")
    name_field = encoded_name + bytes(NAME_SIZE - len(encoded_name))
    metadata = HEADER.pack(
        font.firstchar,
        font.numchars,
        font.encoding,
        font.width,
        font.height,
        font.stride,
        font.bitorder,
        font.byteorder,
    )
    payload = MAGIC + name_field + metadata + font.data
    path.parent.mkdir(parents=True, exist_ok=True)

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=path.parent, prefix=f".{path.name}.", delete=False
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(payload)
            temporary.flush()
            os.fsync(temporary.fileno())
        temporary_path.chmod(0o644)
        os.replace(temporary_path, path)
    except Exception:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="source WSF font")
    parser.add_argument("output", type=Path, help="output WSF font")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--name", required=True)
    args = parser.parse_args()

    source_path = args.source.resolve()
    output_path = args.output.resolve()
    if source_path == output_path:
        parser.error("source and output paths must be different")

    source = read_wsf(source_path)
    output = scale_font(source, args.width, args.height, args.name)
    write_wsf(output, output_path)

    # Parse the completed artifact again rather than trusting the write path.
    checked = read_wsf(output_path)
    if checked != output:
        raise RuntimeError("output did not round-trip through the WSF parser")

    print(
        f"{source.name} {source.width}x{source.height} -> "
        f"{checked.name} {checked.width}x{checked.height}, "
        f"{checked.numchars} glyphs, stride {checked.stride}, "
        f"{output_path.stat().st_size} bytes"
    )


if __name__ == "__main__":
    main()
