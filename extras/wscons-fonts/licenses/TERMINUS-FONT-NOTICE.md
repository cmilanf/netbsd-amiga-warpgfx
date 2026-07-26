# Terminus font notice

`sources/ter-132n.wsf` is NetBSD's packaged 16x32 normal ISO-8859-1 build of
**Terminus Font 4.49.1**, Copyright (C) 2020 Dimitar Toshkov Zhekov.

Terminus Font is licensed under the SIL Open Font License 1.1 with Reserved Font
Name **Terminus Font**. The complete license is in [`OFL-1.1.txt`](OFL-1.1.txt).

Exact source used:

- NetBSD installed path: `/usr/share/wscons/fonts/ter-132n.wsf`
- Source SHA-256:
  `b160154cb0ddafe191a5fa51a6d092630c80444d010b8282e36b9278c23afe8c`

`artifacts/WarpConsole-24x40.wsf` modifies that bitmap by scaling every 16x32
glyph to 24x40 with pixel-centred nearest-neighbour sampling and storing each
row with a four-byte stride for NetBSD's generic rasops renderer. Its embedded
name uses the non-reserved **WarpConsole** name, not the Reserved Font Name.

The modified artifact remains licensed under the SIL Open Font License 1.1.
Its SHA-256 is:

`6743dd2ea651dadd251de71c772f9c3bea17cfa576574cec5d6ce6b687a11911`
