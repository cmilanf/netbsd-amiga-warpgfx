#!/usr/bin/env python3
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from OpenAI GPT-5.6-Sol, Kiro, and
# Anthropic Claude Opus 5.5.
"""Validate and reproducibly regenerate the WarpGFX bonus wscons fonts."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.dont_write_bytecode = True
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

HERE = Path(__file__).resolve().parent
SOURCES = HERE / "sources"
ARTIFACTS = HERE / "artifacts"
sys.path.insert(0, str(HERE))

from generate_scaled_wsf import L2R, WsFont, glyph_pixel, read_wsf  # noqa: E402
from generate_vga_cp437_wsf import read_pcface_fontlist  # noqa: E402

TERMINUS = SOURCES / "ter-132n.wsf"
PCFACE = SOURCES / "PCFace-Oldschool-VGA-8x16-fontlist.js"


@dataclass(frozen=True)
class Artifact:
    filename: str
    source: str  # "terminus" or "vga"
    name: str
    width: int
    height: int
    sha256: str

    @property
    def path(self) -> Path:
        return ARTIFACTS / self.filename


# One entry per shipped font; SHA256.txt carries the same digests.
ARTIFACT_LIST = (
    Artifact("WarpConsole-24x40.wsf", "terminus",
             "WarpConsole-24x40-ISO8859-1", 24, 40,
             "6743dd2ea651dadd251de71c772f9c3bea17cfa576574cec5d6ce6b687a11911"),
    Artifact("WarpConsole-16x30.wsf", "terminus",
             "WarpConsole-16x30-ISO8859-1", 16, 30,
             "f86c3f8b995bf82cde4f7986c515dab5887e6a754de7bf90d4b3bab792a1928b"),
    Artifact("WarpConsole-VGA-CP437-Raw-24x40.wsf", "vga",
             "WarpConsole-VGA-CP437-Raw-24x40", 24, 40,
             "f5b1ff75d7b8ac75461ad0597f512b597aa2c550790275d628b2f08ab5d12cd3"),
    Artifact("WarpConsole-VGA-CP437-Raw-16x28.wsf", "vga",
             "WarpConsole-VGA-CP437-Raw-16x28", 16, 28,
             "d46688ea75114396cfbbfb585249d3c180859d2434298a4fd39ea9bcea91ce17"),
    Artifact("WarpConsole-VGA-CP437-Raw-8x16.wsf", "vga",
             "WarpConsole-VGA-CP437-Raw-8x16", 8, 16,
             "508ba467639b5e08605c17b8c408e9f95e65eda43a18cadaabb3ab8f81b751ce"),
)

SOURCE_HASHES = {
    TERMINUS: "b160154cb0ddafe191a5fa51a6d092630c80444d010b8282e36b9278c23afe8c",
    PCFACE: "f8c59bfc39e52dae72d04406654230d5d4d1a343554bdddfbe11a137d0154cc7",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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
            # Bits beyond the glyph width in the last used byte, then the
            # unused stride bytes, must all be zero.
            used = (output.width + 7) // 8
            if output.width % 8:
                tail = output.data[row + used - 1] & (0xFF >> (output.width % 8))
                if tail != 0:
                    raise AssertionError(
                        f"glyph {glyph:#04x} row {dy} has bits past the width"
                    )
            for byte in output.data[row + used : row + output.stride]:
                if byte != 0:
                    raise AssertionError(
                        f"glyph {glyph:#04x} row {dy} has nonzero padding"
                    )
                padding += 1
    return pixels, padding


def vga_source_font() -> WsFont:
    vga_raw = read_pcface_fontlist(PCFACE)
    if sha256_bytes(vga_raw) != (
        "a8bad6fd78475a6bc2a05438c19207a9bb8c0f4f4099f60384e158cdc3eba580"
    ):
        raise AssertionError("unexpected extracted VGA bitmap hash")
    if vga_raw[0xB3 * 16 : (0xB3 + 1) * 16] != bytes([0x18] * 16):
        raise AssertionError("CP437 0xb3 is not the VGA vertical-line glyph")
    return WsFont(
        "PCFace-Oldschool-VGA-8x16-CP437-Raw", 0, 256, 0, 8, 16, 1,
        L2R, L2R, vga_raw,
    )


def regenerate(artifact: Artifact, output: Path) -> None:
    if artifact.source == "terminus":
        command = [
            sys.executable, str(HERE / "generate_scaled_wsf.py"),
            str(TERMINUS), str(output),
            "--width", str(artifact.width),
            "--height", str(artifact.height),
            "--name", artifact.name,
        ]
    else:
        command = [
            sys.executable, str(HERE / "generate_vga_cp437_wsf.py"),
            str(PCFACE), str(output),
        ]
        # The original 24x40 artifact must keep coming from the defaults.
        if (artifact.width, artifact.height) != (24, 40):
            command += ["--width", str(artifact.width),
                        "--height", str(artifact.height)]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    for path, expected in SOURCE_HASHES.items():
        actual = sha256(path)
        if actual != expected:
            raise AssertionError(f"{path.name}: SHA-256 {actual} != {expected}")
    for artifact in ARTIFACT_LIST:
        actual = sha256(artifact.path)
        if actual != artifact.sha256:
            raise AssertionError(
                f"{artifact.filename}: SHA-256 {actual} != {artifact.sha256}"
            )

    manifest = {}
    for line in (HERE / "SHA256.txt").read_text().splitlines():
        digest, _, name = line.partition("  ")
        manifest[name] = digest
    expected_manifest = {
        f"sources/{path.name}": digest for path, digest in SOURCE_HASHES.items()
    }
    expected_manifest.update({
        f"artifacts/{a.filename}": a.sha256 for a in ARTIFACT_LIST
    })
    if manifest != expected_manifest:
        raise AssertionError("SHA256.txt does not list exactly the pinned files")

    terminus = read_wsf(TERMINUS)
    if (
        terminus.firstchar, terminus.numchars, terminus.encoding,
        terminus.width, terminus.height, terminus.stride,
    ) != (0, 256, 0, 16, 32, 2):
        raise AssertionError("unexpected Terminus source metadata")
    vga = vga_source_font()

    pixels = 0
    padding = 0
    for artifact in ARTIFACT_LIST:
        font = read_wsf(artifact.path)
        if (
            font.name, font.firstchar, font.numchars, font.encoding,
            font.width, font.height, font.stride, font.bitorder,
            font.byteorder,
        ) != (artifact.name, 0, 256, 0, artifact.width, artifact.height,
              4, 1, 1):
            raise AssertionError(f"unexpected {artifact.filename} metadata")
        source = terminus if artifact.source == "terminus" else vga
        counts = check_scaled_pixels(source, font)
        pixels += counts[0]
        padding += counts[1]

    with tempfile.TemporaryDirectory() as temporary:
        temp = Path(temporary)
        for artifact in ARTIFACT_LIST:
            regenerated = temp / artifact.filename
            regenerate(artifact, regenerated)
            if regenerated.read_bytes() != artifact.path.read_bytes():
                raise AssertionError(
                    f"{artifact.filename} regeneration is not byte-identical"
                )

        corrupted = temp / "corrupted.js"
        data = bytearray(PCFACE.read_bytes())
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
        f"PASS: {len(ARTIFACT_LIST)} fonts; hashes, manifest, metadata, "
        f"CP437 slots, deterministic regeneration, {pixels} pixels, "
        f"{padding} padding bytes"
    )


if __name__ == "__main__":
    main()
