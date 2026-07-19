# WarpGFX authorship and provenance audit

New work by Carlos Milán Figueredo with assistance from OpenAI GPT-5.6-Sol. See [LICENSE.md](LICENSE.md) for the applicable license terms.

## Preserved provenance

The audit was performed per source file because the NetBSD tree does not use one universal license. Existing notices were retained as follows:

| File or area | Preserved attribution and terms |
| --- | --- |
| `sys/arch/amiga/dev/warpgfx.c` | The implementation was developed using NetBSD's `zz9k.c` and `zz9k_fb.c` as structural references. Their notice is retained in full: Copyright (c) 2020 The NetBSD Foundation, Inc.; software contributed by Alain Runa; two-clause BSD. Carlos's separate copyright, assistance statement, and two-clause BSD grant follow it. |
| `sys/arch/amiga/dev/warpgfxreg.h` | New WarpGFX register and mode definitions attributed to Carlos under two-clause BSD. Register meanings came from the supplied AmigaOS driver observations and public Zorro identity/configuration facts; uncertain register names remain explicitly descriptive. |
| `sys/arch/amiga/dev/zbus.c` | Existing Copyright (c) 1994 Christian E. Hopps and its original four-clause BSD terms are untouched. The small Warp product-name and print-order additions remain subject to that file's existing terms; the patch does not purport to relicense the file. |
| Existing kernel configuration/build files | Their existing NetBSD notices and per-file licensing status are preserved. |
| `external/mit/xf86-video-wsfb/dist/src/wsfb_exa.c` | New EXA implementation attributed to Carlos under two-clause BSD. It uses public Xorg EXA and NetBSD wsdisplay interfaces; no third-party device-specific acceleration implementation was incorporated. |
| Existing `wsfb.h`, `wsfb_driver.c`, and `wsfb.man` | Copyright (c) 2001/2001-2012 Matthieu Herrb and the existing two-clause BSD license remain. The existing statement that wsfb is based on `fbdev.c`, with authors Alan Hourihane and Michel Dänzer, remains. Carlos and GPT-5.6-Sol are identified for the wsdisplay EXA extensions in the affected source files. |

## Notes

- The mention of GPT-5.6-Sol records authoring assistance. It does not name the model as a copyright holder or replace the human author's attribution.
- This audit is a practical provenance and notice review, not legal advice.
