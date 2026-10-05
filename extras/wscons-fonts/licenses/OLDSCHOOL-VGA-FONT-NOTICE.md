# Oldschool VGA CP437 font notice

`artifacts/WarpConsole-VGA-CP437-Raw-24x40.wsf`,
`artifacts/WarpConsole-VGA-CP437-Raw-16x28.wsf`, and
`artifacts/WarpConsole-VGA-CP437-Raw-8x16.wsf` are adapted from the
**Oldschool VGA 8x16** bitmap in [PC Face](https://github.com/susam/pcface),
which is generated from **Oldschool PC Fonts version 2.2** by **VileR**.
Oldschool PC Fonts are faithful reproductions of original IBM PC OEM fonts,
with minor documented corrections.

Exact source used:

- PC Face commit: `8629ba46b73f58ac88cacbe8e77c6e9975dd221c`
- Upstream path: `out/oldschool-vga-8x16/fontlist.js`
- Preserved file: `sources/PCFace-Oldschool-VGA-8x16-fontlist.js`
- Source SHA-256:
  `f8c59bfc39e52dae72d04406654230d5d4d1a343554bdddfbe11a137d0154cc7`
- Extracted 4,096-byte bitmap SHA-256:
  `a8bad6fd78475a6bc2a05438c19207a9bb8c0f4f4099f60384e158cdc3eba580`
- Source page: <https://github.com/susam/pcface/tree/8629ba46b73f58ac88cacbe8e77c6e9975dd221c/out/oldschool-vga-8x16>
- Original-font project: <https://int10h.org/oldschool-pc-fonts/>

PC Face states that its Oldschool PC Font bitmaps may be used under either GPL
v3 or Creative Commons Attribution-ShareAlike 4.0. This adaptation uses **CC
BY-SA 4.0**. The complete license is preserved in
[`CC-BY-SA-4.0.txt`](CC-BY-SA-4.0.txt), and its canonical URI is
<https://creativecommons.org/licenses/by-sa/4.0/>.

## Modifications

The generator:

1. extracts all 256 glyphs in their original CP437 slot order;
2. scales each 8x16 bitmap to 24x40 or 16x28 with pixel-centred
   nearest-neighbour sampling (the 8x16 artifact keeps the original pixels);
3. stores each row with the four-byte stride required by generic rasops; and
4. deliberately labels the WSF as NetBSD ISO/direct encoding rather than IBM
   encoding.

The fourth change is required for raw ANSI/BBS byte streams on NetBSD's
`wsemul_vt100`. That emulator interprets bytes `0x80`-`0xff` as the
same-numbered Unicode Latin-1 code points. ISO wsfont encoding selects the
same-numbered glyph slot directly, so raw CP437 byte `0xb3` reaches CP437 glyph
slot `0xb3` (vertical line). IBM wsfont encoding would instead try to remap
Unicode `U+00B3`, producing the wrong result.

The resulting WSF files and their bitmaps are licensed under CC BY-SA 4.0. No
endorsement by VileR, Susam Pal/PC Face, IBM, or the Oldschool PC Fonts project
is implied. Artifact SHA-256:

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `WarpConsole-VGA-CP437-Raw-24x40.wsf` | 24x40 | `f5b1ff75d7b8ac75461ad0597f512b597aa2c550790275d628b2f08ab5d12cd3` |
| `WarpConsole-VGA-CP437-Raw-16x28.wsf` | 16x28 | `d46688ea75114396cfbbfb585249d3c180859d2434298a4fd39ea9bcea91ce17` |
| `WarpConsole-VGA-CP437-Raw-8x16.wsf` | 8x16 | `508ba467639b5e08605c17b8c408e9f95e65eda43a18cadaabb3ab8f81b751ce` |
