# WarpGFX: NetBSD/amiga kernel driver and accelerated Xorg/wsfb

[NetBSD/amiga](https://wiki.netbsd.org/ports/amiga/) [wsdisplay](https://man.netbsd.org/wsdisplay.4) driver for the [CS-Lab Warp 1260](https://amigawarp.eu/product/warp-1260-board-for-amiga-1200/) RTG hardware, with **hardware-accelerated** console and [Xorg EXA](https://man.netbsd.org/exa.4) support.

> **DISCLAIMER**  
> This software is provided **AS IS**, without warranty of any kind, express or implied. There is no guarantee that it will work as described or that it is fit for any particular purpose. You use it entirely at your own risk. Because this project modifies kernel and Xorg components and drives real hardware, you are responsible for reviewing the source code, verifying its correct behavior in your own environment, and keeping backups and known-good fallbacks before installing or running any of it. The author accepts no liability for any damage, data loss, or other consequences arising from its use.
>
> **The code on this repository was developed with the assitance from Kiro and OpenAI GPT-5.6-Sol**

The build and installation instructions are intended to be run from a NetBSD host. NetBSD's cross-build system supports building the `amiga` target from a different host architecture, so an `amd64` NetBSD machine can compile the amiga kernel and Xorg components; an Amiga host is not required for compilation.

Features:

- six 16-bit `R5G6B5` video modes: 640x480, 800x600, 1024x768, 1280x720, 1280x1024, and 1920x1080;
- hardware rectangle fill/copy acceleration for the wscons console;
- EXA Solid/Copy acceleration for Xorg through the standard wsfb driver;
- red XOR text cursor, multiple virtual screens, and optional 80x25 geometry;
- the unconfigured Warp 1260 QSPI Flash device (product 5120/102) is identified but not accessed.

## Screenshots and video

<table>
  <tr>
    <td width="50%" align="center">
      <a href="https://youtu.be/iFda9PB3n1w">
        <img src="screenshots/netbsd-amiga-warpgfx-x11-spinning-cube.png" width="100%" alt="X11 spinning-cube demo running on NetBSD/amiga with WarpGFX">
      </a>
      <br>
      <sub><strong>X11 spinning-cube demo</strong> — select the image to watch the video on YouTube. <a href="screenshots/netbsd-amiga-warpgfx-x11-spinning-cube.png">View full size</a>.</sub>
    </td>
    <td width="50%" align="center">
      <a href="screenshots/netbsd-amiga-warpgfx-test.png">
        <img src="screenshots/netbsd-amiga-warpgfx-test.png" width="100%" alt="WarpGFX display test running on NetBSD/amiga">
      </a>
      <br>
      <sub><strong>WarpGFX display test</strong> running on NetBSD/amiga. Select the image to view full size.</sub>
    </td>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <a href="screenshots/netbsd-amiga-warpgfx-dmesg.png">
        <img src="screenshots/netbsd-amiga-warpgfx-dmesg.png" alt="NetBSD kernel messages showing the WarpGFX devices">
      </a>
      <br>
      <sub><strong>Kernel detection</strong> of the WarpGFX devices. Select the image to view full size.</sub>
    </td>
  </tr>
</table>

## Performance testing

[x11perf](https://man.netbsd.org/x11perf.1) has been used to benchmark the driver improvements with the `rect100` and `copywinwin100` tests:

```shell
/usr/X11R7/bin/x11perf -sync -reps 100 -rect100
/usr/X11R7/bin/x11perf -sync -reps 100 -copywinwin100
```

Results are available in the `testing/x11perf` folder. The following table is a summary of the test:

| Test | Video mode | Chipset | EXA | Average result | Improvement |
| ---- | ---------- | ------- | --- | -------------- | ----------- |
| rect100 | 640x480 8 bit | AGA | No | 377.4 ops/sec | 1x (baseline) |
| copywinwin100 | 640x480 8 bit | AGA | No | 119.2 ops/sec | 1x (baseline) |
| rect100 | 1920x1080 16 bit | WarpGFX | No | 1010.0 ops/sec | 2.68x |
| copywinwin100 | 1920x1080 16 bit | WarpGFX | No | 113.0 ops/sec | 0.95x |
| rect100 | 1920x1080 16 bit | WarpGFX | Solid Copy | 4910.0 ops/sec | 13.01x |
| copywinwin100 | 1920x1080 16 bit | WarpGFX | Solid Copy | 275.0 ops/sec | 2.31x |

  - **Test**. The `x11perf` test.
  - **Video mode**. Display resolution and color depth used in the test.
  - **Chipset**. Whatever Amiga Custom Chips (AGA in this case) or Warp RTG was used.
  - **EXA**. If X11 EXA hardware acceleration was used and for which operations.
  - **Average results**. Average operations per seccond.
  - **Improvement**. Improvement compared to AGA as baseline.

## Release files

- `src/` and `xsrc/`: modified files at their complete upstream-relative paths;
- `netbsd-src-warpgfx.patch` and `netbsd-xsrc-warpgfx-wsfb-exa.patch`: complete patches for clean, matching NetBSD source trees;
- `scripts/patch-config.sh`: the single machine-readable source of truth for upstream URLs, pinned base commits, and managed paths;
- `scripts/generate-patches.sh`: regenerates patches at the configured bases;
- `scripts/update-patches.sh`: three-way rebases both patches onto newer bases;
- `scripts/build-netbsd-amiga.sh`: end-to-end NetBSD build script for the amiga kernel and Xorg wsfb driver;
- `ATTRIBUTIONS.md`: authorship, provenance, and licensing record.

`build-netbsd-amiga.sh` is supported only on NetBSD and rejects other hosts. The maintenance scripts `generate-patches.sh` and `update-patches.sh` use POSIX `/bin/sh` and are supported on NetBSD, Linux, and macOS. They require Git 2.25 or newer for sparse-checkout and partial-clone support, plus one available SHA-256 command: `sha256`, `shasum`, or `sha256sum`. `patch-config.sh` is portable sourced configuration rather than a standalone command. Its managed path lists are whitespace-delimited, so managed paths must not contain whitespace or shell wildcard characters.

The `src/` and `xsrc/` directories contain every modified file, not copies of all untouched files in the very large upstream repositories. Do not apply a complete patch to a tree that already contains an earlier WarpGFX patch.

The clean base commits are the unmodified upstream revisions against which the patches are generated. Their immutable commit IDs are in `scripts/patch-config.sh`. To clone the official mirrors and check out those exact bases:

```sh
. ./scripts/patch-config.sh
git clone "$SRC_URL" "$HOME/netbsd-amiga-warpgfx-build/src"
git -C "$HOME/netbsd-amiga-warpgfx-build/src" checkout "$SRC_BASE"
git clone "$XSRC_URL" "$HOME/netbsd-amiga-warpgfx-build/xsrc"
git -C "$HOME/netbsd-amiga-warpgfx-build/xsrc" checkout "$XSRC_BASE"
```

Current release checksums are in `SHA256.txt`.

## Automated NetBSD build

On a NetBSD host, `scripts/build-netbsd-amiga.sh` checks the base build environment and Git package, verifies the release patches, fetches the pinned `src` and `xsrc` commits, builds amiga tools, the kernel, and Xorg, and copies the kernel and accelerated `wsfb` module into `output/`:

```sh
./scripts/build-netbsd-amiga.sh
```

Select a CPU-specific kernel configuration and WarpGFX options when needed:

```sh
./scripts/build-netbsd-amiga.sh --cpu 68060 \
  --warpgfx console,accel,mode=1080,no-debug --jobs 2
```

`--cpu` accepts `68030`, `68040`, or `68060`. It generates a small kernel configuration that includes `WSCONS` and disables the other CPU options; NetBSD then selects the appropriate compiler flags automatically. Omitting `--cpu` preserves NetBSD's default amiga CPU support. WarpGFX defaults are `console,accel,mode=720,no-debug`. Run the script with `--help` for supported modes, option tokens, workspace, and output controls.

Kernel builds are reproducible by default: the script passes `MKREPRO=yes`, preventing the kernel version string from embedding the build username, hostname, timestamp, and object directory. Pass `--non-reproducible` to restore NetBSD's traditional version string with those host details. The generated version object is refreshed on every run so switching modes cannot reuse stale metadata from the persistent build cache.

Use `--only-kernel` when an Xorg rebuild is unnecessary:

```sh
./scripts/build-netbsd-amiga.sh --only-kernel --cpu 68060 \
  --warpgfx console,accel,mode=1080,no-debug
```

Kernel-only mode requires an existing `tools-amiga` cache from a previous full build. It reuses those cross-tools without running the tools target, executes only the kernel build target, and writes the kernel plus `BUILD-INFO.txt` to `output/`. It does not build the Xorg distribution or `wsfb` driver. An existing `output/wsfb_drv.so.0` is left unchanged and is not listed in the new build metadata. On a fresh workspace, run one full build before using `--only-kernel`.

The default workspace, `~/netbsd-amiga-warpgfx-build`, is persistent. The first run downloads the pinned `src` and `xsrc` commits and builds all artifacts; later runs validate those commits and the exact WarpGFX patch state, then use NetBSD's update mode to rebuild only what changed. Existing workspaces created by earlier versions of this script are accepted when their source trees match the pinned commits and patches. If the repository patches changed, `--reset-sources` validates the cached checkouts, runs `git reset --hard` and `git clean -fd` only inside the workspace's `src` and `xsrc` trees, and reapplies the current patches while preserving `obj-amiga` and `tools-amiga`. This intentionally discards any edits in those cached source trees. A workspace lock prevents concurrent builds from sharing objects. If the configured revisions changed, the source trees contain edits that must be preserved, or a stale lock remains after an interrupted host, use a new `--work-dir`; remove `.build-lock` manually only after confirming no build is running.

NetBSD-generated object and tool files embed absolute source, object, and tool paths. Do not rename a populated build workspace if its caches must remain reusable; `--reset-sources` does not rewrite those cached paths. If a workspace has already moved, retain the original path as a symlink to the new physical directory and continue passing the original path to `--work-dir` for the lifetime of that cache. Otherwise remove `obj-amiga` and `tools-amiga` and rebuild them at the new path.

The script builds without installing anything and prints kernel, Xorg module, rollback, configuration, and verification guidance when it completes.

## Modify sources and regenerate patches

Edit managed files directly under `src/` and `xsrc/`, preserving their paths, then run:

```sh
./scripts/generate-patches.sh
```

The script sparsely fetches the pinned clean commits, overlays the vendored files, checks whitespace, verifies normal and reverse patch application, and updates both patches and `SHA256.txt`.

## Update to newer NetBSD-current bases

First commit or revert changes to the managed overlays, patches, configuration, and checksum file. Preview a rebase onto the current HEAD of each official mirror without changing this repository:

```sh
./scripts/update-patches.sh --latest --dry-run
```

If it succeeds, perform the update:

```sh
./scripts/update-patches.sh --latest
```

For a reproducible selected pair instead of moving HEADs:

```sh
./scripts/update-patches.sh --src SRC_COMMIT --xsrc XSRC_COMMIT
```

The updater verifies that the existing patches reproduce all vendored files, resolves targets to full commit IDs, requires fast-forward history by default, and cherry-picks each patch as a synthetic commit onto its new base. It rejects changes outside the managed path lists, unsupported deletions or file-type changes, whitespace errors, and any result that fails forward/reverse application or exact tree comparison. Both repositories must pass before a rollback-protected transaction replaces overlays, patches, pins, and checksums.

On a merge conflict the script changes no repository files and retains its temporary Git trees for inspection. `--keep-temp` also retains successful work; `--allow-non-fast-forward` permits a history rewrite only when explicitly requested. A clean textual rebase does not prove source or ABI compatibility: build the amiga kernel and Xorg wsfb module below before publishing. Also note that src and xsrc mirror HEADs are resolved independently and may not represent an atomically published pair; explicit reviewed commits are preferable for a release.

## Apply to clean trees

```sh
cd "$HOME/netbsd-amiga-warpgfx-build/src"
git apply --check /path/to/netbsd-src-warpgfx.patch
git apply /path/to/netbsd-src-warpgfx.patch

cd "$HOME/netbsd-amiga-warpgfx-build/xsrc"
git apply --check /path/to/netbsd-xsrc-warpgfx-wsfb-exa.patch
git apply /path/to/netbsd-xsrc-warpgfx-wsfb-exa.patch
```

For non-Git source trees, use `patch -p1 < patch-file` instead.

## Kernel configuration and build

The base kernel configuration is `$HOME/netbsd-amiga-warpgfx-build/src/sys/arch/amiga/conf/WSCONS`. For example, to build a M68060-only kernel, create `WSCONS060` alongside it as a derived configuration; selecting only `M68060` makes the NetBSD build system supply the correct compiler flags:

```text
include "arch/amiga/conf/WSCONS"

# Generate code exclusively for the Motorola 68060.
no options M68020
no options M68030
no options M68040

# 68040-only and generic FPU support are unnecessary.
no options FPSP
no options FPU_EMULATE
```

You can follow the same procedure if you want an optimized kernel for M68030 or M68040. Notice that M68020 lacks MMU, so it would require a M68851 to work with NetBSD, a configuration that no Amiga computer featured.

The relevant WarpGFX options in `WSCONS` are:

```text
warpgfx* at zbus?
options  WARPGFX_CONSOLE
options  WARPGFX_ACCEL
options  WARPGFX_MODE=1080
#options WARPGFX_DEBUG
```

Supported 16-bit mode values are `480`, `600`, `720`, `768`, `1024`, and `1080`. Omitting `WARPGFX_DEBUG` suppresses register dumps; normal device and acceleration status lines remain.

```sh
cd "$HOME/netbsd-amiga-warpgfx-build/src"
./build.sh -m amiga \
  -O "$HOME/netbsd-amiga-warpgfx-build/obj-amiga" \
  -T "$HOME/netbsd-amiga-warpgfx-build/tools-amiga" \
  -V MKREPRO=yes \
  -j2 kernel=WSCONS060
```

`MKREPRO=yes` omits host-specific provenance from the kernel version string. Leave out `-V MKREPRO=yes` only when the traditional build username, hostname, timestamp, and object path are intentionally wanted.

Keep the currently working kernel available as a fallback before installing the new one.

## Build the Xorg wsfb module

Full build:

```sh
cd "$HOME/netbsd-amiga-warpgfx-build/src"
./build.sh -m amiga \
  -O "$HOME/netbsd-amiga-warpgfx-build/obj-amiga" \
  -T "$HOME/netbsd-amiga-warpgfx-build/tools-amiga" \
  -D "$HOME/netbsd-amiga-warpgfx-build/obj-amiga/destdir.amiga" \
  -X "$HOME/netbsd-amiga-warpgfx-build/xsrc" \
  -x -u -j2 distribution
```

Targeted rebuild, when the destination tree already has the required Xorg headers and libraries:

```sh
cd "$HOME/netbsd-amiga-warpgfx-build/src/external/mit/xorg/server/drivers/xf86-video-wsfb"
env DESTDIR="$HOME/netbsd-amiga-warpgfx-build/obj-amiga/destdir.amiga" \
    X11SRCDIR="$HOME/netbsd-amiga-warpgfx-build/xsrc" \
    MKX11=yes \
    "$HOME/netbsd-amiga-warpgfx-build/tools-amiga/bin/nbmake-amiga" cleandir dependall install
```

The resulting module is normally:

```text
$HOME/netbsd-amiga-warpgfx-build/obj-amiga/destdir.amiga/usr/X11R7/lib/modules/drivers/wsfb_drv.so.0
```

Stop X before replacing the installed module and retain the previous module as a fallback.

## Xorg configuration and verification

The accelerated device section in `/etc/X11/xorg.conf` is:

```text
Section "Device"
    Identifier "WarpGFX"
    Driver "wsfb"
    Option "Device" "/dev/ttyE0"
    Option "ShadowFB" "false"
    Option "Accel" "true"
    Option "HWCursor" "false"
EndSection
```

Verify the active paths with:

```sh
grep -E 'wsdisplay EXA|ShadowFB' /var/log/Xorg.0.log
dmesg | grep -E 'warpqspi|console/wsfb acceleration'
```

The expected Xorg message is:

```text
Using wsdisplay EXA fill/copy acceleration
```

If acceleration causes a regression, `Option "Accel" "false"` selects the already working direct wsfb path without rebuilding.
