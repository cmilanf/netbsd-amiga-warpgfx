# Terminus font notice

`sources/ter-132n.wsf` is NetBSD's packaged 16x32 normal ISO-8859-1 build of
**Terminus Font 4.49.1**, Copyright (C) 2020 Dimitar Toshkov Zhekov.

Terminus Font is licensed under the SIL Open Font License 1.1 with Reserved Font
Name **Terminus Font**. The complete license is in [`OFL-1.1.txt`](OFL-1.1.txt).

Exact source used:

- NetBSD installed path: `/usr/share/wscons/fonts/ter-132n.wsf`
- Source SHA-256:
  `b160154cb0ddafe191a5fa51a6d092630c80444d010b8282e36b9278c23afe8c`

Two artifacts modify that bitmap by rescaling every 16x32 glyph with
pixel-centred nearest-neighbour sampling and storing each row with a four-byte
stride for NetBSD's generic rasops renderer:

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `artifacts/WarpConsole-24x40.wsf` | 24x40 | `6743dd2ea651dadd251de71c772f9c3bea17cfa576574cec5d6ce6b687a11911` |
| `artifacts/WarpConsole-16x30.wsf` | 16x30 | `f86c3f8b995bf82cde4f7986c515dab5887e6a754de7bf90d4b3bab792a1928b` |

Their embedded names use the non-reserved **WarpConsole** name, not the
Reserved Font Name. The modified artifacts remain licensed under the SIL Open
Font License 1.1.

The 640x480 example configuration uses NetBSD's own unmodified
`/usr/share/wscons/fonts/ter-116n.wsf` (Terminus 8x16) in place; this bundle
does not copy or modify it.
