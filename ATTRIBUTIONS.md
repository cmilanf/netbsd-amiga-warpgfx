# WarpGFX authorship and provenance audit

This project was developed with the assistance of Kiro, OpenAI GPT-5.6-Sol, and Anthropic Claude Opus 5.5. See [LICENSE.md](LICENSE.md) for the applicable license terms.

## Preserved provenance

The audit was performed per source file because the NetBSD tree does not use one universal license. Existing notices were retained as follows:

| File or area | Preserved attribution and terms |
| --- | --- |
| `sys/arch/amiga/dev/warpgfx.c` | The implementation was developed using NetBSD's `zz9k.c` and `zz9k_fb.c` as structural references. Their notice is retained in full: Copyright (c) 2020 The NetBSD Foundation, Inc.; software contributed by Alain Runa; two-clause BSD. Carlos's separate copyright, assistance statement, and two-clause BSD grant follow it. |
| `sys/arch/amiga/dev/warpgfxreg.h` | New WarpGFX register and mode definitions, carrying Carlos Milán Figueredo's copyright notice and the two-clause BSD license. Register meanings came from observing the supplied AmigaOS drivers (`csgfx.card` 17.68 and 22.96) and public Zorro identity/configuration facts; uncertain register names remain explicitly descriptive. No AmigaOS code is copied or translated. |
| `sys/arch/amiga/dev/zbus.c` | Existing Copyright (c) 1994 Christian E. Hopps and its original four-clause BSD terms are untouched. The small Warp product-name and print-order additions remain subject to that file's existing terms; the patch does not purport to relicense the file. |
| Existing kernel configuration/build files | Their existing NetBSD notices and per-file licensing status are preserved. |
| `external/mit/xf86-video-wsfb/dist/src/wsfb_exa.c` | New EXA implementation, carrying Carlos Milán Figueredo's copyright notice and the two-clause BSD license. It uses public Xorg EXA and NetBSD wsdisplay interfaces; no third-party device-specific acceleration implementation was incorporated. |
| Existing `wsfb.h`, `wsfb_driver.c`, and `wsfb.man` | Copyright (c) 2001/2001-2012 Matthieu Herrb and the existing two-clause BSD license remain. The existing statement that wsfb is based on `fbdev.c`, with authors Alan Hourihane and Michel Dänzer, remains. Carlos and GPT-5.6-Sol are identified for the wsdisplay EXA extensions in the affected source files. |

## Diagnostic tools

| File or area | Attribution and terms |
| --- | --- |
| `diag/` | New tools under the repository's BSD 2-Clause license, developed with the assistance of Kiro and Anthropic Claude Opus 5.5. The tools use the public NetBSD `/dev/mem` and wsdisplay interfaces and the register knowledge recorded in `warpgfxreg.h`; no third-party code is incorporated. |

## Optional wscons font extras

The optional `extras/wscons-fonts/` bundle is outside the NetBSD `src`/`xsrc`
overlay and does not alter the licensing of the WarpGFX driver or patches.
Licensing is scoped as follows:

| File or area | Preserved attribution and terms |
| --- | --- |
| `sources/ter-132n.wsf`, `artifacts/WarpConsole-24x40.wsf`, `artifacts/WarpConsole-16x30.wsf` | Terminus Font 4.49.1, Copyright (C) 2020 Dimitar Toshkov Zhekov, under SIL Open Font License 1.1 with Reserved Font Name "Terminus Font". The derivatives use the non-reserved WarpConsole name. The 640x480 example configuration uses NetBSD's installed `ter-116n.wsf` unmodified and in place. Exact source hash and modifications are recorded in `licenses/TERMINUS-FONT-NOTICE.md`. |
| `sources/PCFace-Oldschool-VGA-8x16-fontlist.js`, `artifacts/WarpConsole-VGA-CP437-Raw-24x40.wsf`, `-16x28.wsf`, `-8x16.wsf` | PC Face Oldschool VGA bitmap generated from Oldschool PC Fonts 2.2 by VileR. Distributed here under CC BY-SA 4.0 with pinned PC Face commit, source hash, modification record, and no-endorsement notice in `licenses/OLDSCHOOL-VGA-FONT-NOTICE.md`. |
| Font generators, validator, installer, example configuration, and bundle documentation | Under the repository's BSD 2-Clause license, developed with the assistance of OpenAI GPT-5.6-Sol, Kiro, and Anthropic Claude Opus 5.5. |

## Notes

- The mentions of Kiro, OpenAI GPT-5.6-Sol, and Anthropic Claude Opus 5.5 record development assistance. They do not name the tools or models as copyright holders.
- This audit is a practical provenance and notice review, not legal advice.
