#!/usr/bin/env python3
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from OpenAI GPT-5.6-Sol.
"""Validate and reproducibly regenerate the WarpGFX bonus wscons fonts."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

HERE = Path(__file__).resolve().parent
SOURCES = HERE / "sources"
ARTIFACTS = HERE / "artifacts"
sys.path.insert(0, str(HERE))

from generate_scaled_wsf import L2R, WsFont, glyph_pixel, read_wsf  # noqa: E402
from generate_vga_cp437_wsf import read_pcface_fontlist  # noqa: E402

HASHES = {
    SOURCES / "ter-132n.wsf":
        "b160154cb0ddafe191a5fa51a6d092630c80444d010b8282e36b9278c23afe8c",
    SOURCES / "PCFace-Oldschool-VGA-8x16-fontlist.js":
        "f8c59bfc39e52dae72d04406654230d5d4d1a343554bdddfbe11a137d0154cc7",
    ARTIFACTS / "WarpConsole-24x40.wsf":
        "6743dd2ea651dadd251de71c772f9c3bea17cfa576574cec5d6ce6b687a11911",
    ARTIFACTS / "WarpConsole-VGA-CP437-Raw-24x40.wsf":
        "f5b1ff75d7b8ac75461ad0597f512b597aa2c550790275d628b2f08ab5d12cd3",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_scaled_pixels(source: WsFont, output: WsFont) -> tuple[int, int]:
    if source.numchars != output.numchars:
        raise AssertionError("source/output glyph count differs")
    pixels = 0
    padding = 0
    for glyph in range(output.numchars):
        for dy in range(output.height):
            sy = min(
                source.height - 1,
                ((2 * dy + 1) * source.height) // (2 * output.height),
            )
            row = (glyph * output.height + dy) * output.stride
            for dx in range(output.width):
                sx = min(
                    source.width - 1,
                    ((2 * dx + 1) * source.width) // (2 * output.width),
                )
                actual = glyph_pixel(output, glyph, dx, dy)
                expected = glyph_pixel(source, glyph, sx, sy)
                if actual != expected:
                    raise AssertionError(
                        f"glyph {glyph:#04x} pixel ({dx}, {dy}) differs"
                    )
                pixels += 1
            for byte in output.data[
                row + (output.width + 7) // 8 : row + output.stride
            ]:
                if byte != 0:
                    raise AssertionError(
                        f"glyph {glyph:#04x} row {dy} has nonzero padding"
                    )
                padding += 1
    return pixels, padding


def main() -> None:
    for path, expected in HASHES.items():
        actual = sha256(path)
        if actual != expected:
            raise AssertionError(f"{path.name}: SHA-256 {actual} != {expected}")

    iso_source = read_wsf(SOURCES / "ter-132n.wsf")
    iso_output = read_wsf(ARTIFACTS / "WarpConsole-24x40.wsf")
    if (
        iso_source.firstchar,
        iso_source.numchars,
        iso_source.encoding,
        iso_source.width,
        iso_source.height,
        iso_source.stride,
    ) != (0, 256, 0, 16, 32, 2):
        raise AssertionError("unexpected Terminus source metadata")
    if (
        iso_output.name,
        iso_output.firstchar,
        iso_output.numchars,
        iso_output.encoding,
        iso_output.width,
        iso_output.height,
        iso_output.stride,
        iso_output.bitorder,
        iso_output.byteorder,
    ) != ("WarpConsole-24x40-ISO8859-1", 0, 256, 0, 24, 40, 4, 1, 1):
        raise AssertionError("unexpected ISO artifact metadata")

    vga_raw = read_pcface_fontlist(
        SOURCES / "PCFace-Oldschool-VGA-8x16-fontlist.js"
    )
    if sha256_bytes(vga_raw) != (
        "a8bad6fd78475a6bc2a05438c19207a9bb8c0f4f4099f60384e158cdc3eba580"
    ):
        raise AssertionError("unexpected extracted VGA bitmap hash")
    vga_source = WsFont(
        "PCFace-Oldschool-VGA-8x16-CP437-Raw",
        0,
        256,
        0,
        8,
        16,
        1,
        L2R,
        L2R,
        vga_raw,
    )
    vga_output = read_wsf(
        ARTIFACTS / "WarpConsole-VGA-CP437-Raw-24x40.wsf"
    )
    if (
        vga_output.name,
        vga_output.firstchar,
        vga_output.numchars,
        vga_output.encoding,
        vga_output.width,
        vga_output.height,
        vga_output.stride,
        vga_output.bitorder,
        vga_output.byteorder,
    ) != ("WarpConsole-VGA-CP437-Raw-24x40", 0, 256, 0, 24, 40, 4, 1, 1):
        raise AssertionError("unexpected VGA artifact metadata")

    vertical = vga_raw[0xB3 * 16 : (0xB3 + 1) * 16]
    if vertical != bytes([0x18] * 16):
        raise AssertionError("CP437 0xb3 is not the VGA vertical-line glyph")

    iso_counts = check_scaled_pixels(iso_source, iso_output)
    vga_counts = check_scaled_pixels(vga_source, vga_output)

    with tempfile.TemporaryDirectory() as temporary:
        temp = Path(temporary)
        iso_regen = temp / "iso.wsf"
        vga_regen = temp / "vga.wsf"
        subprocess.run(
            [
                sys.executable,
                str(HERE / "generate_scaled_wsf.py"),
                str(SOURCES / "ter-132n.wsf"),
                str(iso_regen),
                "--width",
                "24",
                "--height",
                "40",
                "--name",
                "WarpConsole-24x40-ISO8859-1",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        subprocess.run(
            [
                sys.executable,
                str(HERE / "generate_vga_cp437_wsf.py"),
                str(SOURCES / "PCFace-Oldschool-VGA-8x16-fontlist.js"),
                str(vga_regen),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        if iso_regen.read_bytes() != iso_output_path().read_bytes():
            raise AssertionError("ISO regeneration is not byte-identical")
        if vga_regen.read_bytes() != vga_output_path().read_bytes():
            raise AssertionError("VGA regeneration is not byte-identical")

        corrupted = temp / "corrupted.js"
        data = bytearray(
            (SOURCES / "PCFace-Oldschool-VGA-8x16-fontlist.js").read_bytes()
        )
        data[100] ^= 1
        corrupted.write_bytes(data)
        result = subprocess.run(
            [
                sys.executable,
                str(HERE / "generate_vga_cp437_wsf.py"),
                str(corrupted),
                str(temp / "corrupted.wsf"),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode == 0 or "does not match expected" not in result.stderr:
            raise AssertionError("VGA generator accepted a corrupted source")

    print(
        "PASS: hashes, metadata, CP437 slots, deterministic regeneration, "
        f"{iso_counts[0] + vga_counts[0]} pixels, "
        f"{iso_counts[1] + vga_counts[1]} padding bytes"
    )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def iso_output_path() -> Path:
    return ARTIFACTS / "WarpConsole-24x40.wsf"


def vga_output_path() -> Path:
    return ARTIFACTS / "WarpConsole-VGA-CP437-Raw-24x40.wsf"


if __name__ == "__main__":
    main()
