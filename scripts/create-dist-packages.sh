#!/bin/sh
# Package WarpGFX matrix kernels and accelerated wsfb modules into
# per-combination .tar.gz and .lha archives and (optionally) publish them as
# GitHub releases, one release per NetBSD version. Asset names follow:
#
#   netbsd-amiga-<version>-warpgfx-<warpgfx-version>-<cpu>-<resolution>.tar.gz
#   netbsd-amiga-<version>-warpgfx-<warpgfx-version>-<cpu>-<resolution>.lha
#
# where <version> is the release label with its leading "netbsd-" stripped
# (e.g. 11.0, current), <cpu> is 68030|68040|68060, and <resolution> is the
# pixel geometry mapped from the WARPGFX_MODE token (720 -> 1280x720, etc.).
#
# Building archives is always safe and local. Uploading to GitHub happens only
# with --publish; without it the script builds archives and prints the exact gh
# commands it would run (a dry run).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INPUT=$ROOT/output
DIST=
FORMATS='tar.gz lha'
RELEASES=
TAG_PREFIX='warpgfx-'
REPO=
KERNEL_NAME='netbsd-warpgfx'
PUBLISH=0
PRERELEASE=auto
# Driver software version, for the release notes. Defaults to the value of
# WARPGFX_VERSION in the driver header; override with --driver-version.
DRIVER_VERSION=$(sed -n 's/.*#define[[:space:]][[:space:]]*WARPGFX_VERSION[[:space:]][[:space:]]*"\([^"]*\)".*/\1/p' \
    "$ROOT/src/sys/arch/amiga/dev/warpgfxreg.h" 2>/dev/null | head -1)

usage() {
    cat >&2 <<EOF
usage: $0 [options]

      --input DIR       matrix output dir (default: repo output/).
                        Expects <label>/<cpu>-<mode>/{netbsd-warpgfx,wsfb_drv.so.0}.
      --dist DIR        where to write archives (default: <input>/dist)
      --releases "L .." labels to package (default: all present under --input)
      --formats "..."   subset of "tar.gz lha" (default: both)
      --tag-prefix STR  GitHub tag prefix (default: warpgfx-)
      --repo OWNER/NAME gh repository (default: auto-detected by gh)
      --kernel-name N   filename of the kernel inside each archive
                        (default: netbsd-warpgfx)
      --driver-version V  WarpGFX driver version shown in the notes
                        (default: WARPGFX_VERSION from the driver header)
      --prerelease      mark GitHub releases as prerelease
      --stable          mark GitHub releases as full releases
                        (default: auto - prerelease for RC/current/.99 versions)
      --publish         actually create/upload GitHub releases (default: dry run)
  -h, --help            show this help

Each NetBSD version becomes one GitHub release tagged <tag-prefix><version>
containing that version's archives plus a SHA256SUMS file. Re-running --publish
updates existing releases and clobbers changed assets.
EOF
}

die() { echo "error: $*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
need_arg() { [ "$#" -ge 2 ] && [ -n "$2" ] || { usage; exit 2; }; }

while [ "$#" -gt 0 ]; do
    case $1 in
        --input) need_arg "$@"; INPUT=$2; shift 2 ;;
        --dist) need_arg "$@"; DIST=$2; shift 2 ;;
        --releases) need_arg "$@"; RELEASES=$2; shift 2 ;;
        --formats) need_arg "$@"; FORMATS=$2; shift 2 ;;
        --tag-prefix) need_arg "$@"; TAG_PREFIX=$2; shift 2 ;;
        --repo) need_arg "$@"; REPO=$2; shift 2 ;;
        --kernel-name) need_arg "$@"; KERNEL_NAME=$2; shift 2 ;;
        --driver-version) need_arg "$@"; DRIVER_VERSION=$2; shift 2 ;;
        --prerelease) PRERELEASE=1; shift ;;
        --stable) PRERELEASE=0; shift ;;
        --publish) PUBLISH=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

case $INPUT in /*) ;; *) INPUT=$PWD/$INPUT ;; esac
[ -d "$INPUT" ] || die "input directory not found: $INPUT"
[ -n "$DIST" ] || DIST=$INPUT/dist
case $DIST in /*) ;; *) DIST=$PWD/$DIST ;; esac

# The driver version is part of every asset filename, so it must be present
# and safe to embed in a filename.
[ -n "$DRIVER_VERSION" ] || die "driver version is empty; set WARPGFX_VERSION in the driver header or pass --driver-version"
case $DRIVER_VERSION in
    *[!A-Za-z0-9._-]*) die "driver version '$DRIVER_VERSION' has characters unsafe for a filename" ;;
esac

# Tool checks.
command -v tar >/dev/null 2>&1 || die "tar is required"
command -v gzip >/dev/null 2>&1 || die "gzip is required"
WANT_LHA=0
for f in $FORMATS; do
    case $f in
        tar.gz) ;;
        lha) WANT_LHA=1 ;;
        *) die "unsupported format '$f' (use tar.gz and/or lha)" ;;
    esac
done
[ "$WANT_LHA" -eq 0 ] || command -v lha >/dev/null 2>&1 || \
    die "lha is required for the lha format (install lhasa or lha)"
if [ "$PUBLISH" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required for --publish"
    gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"
fi

sha256_file() {
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | sed 's/[[:space:]].*//'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | sed 's/[[:space:]].*//'
    else die "sha256, shasum, or sha256sum is required"; fi
}

# Map a WARPGFX_MODE token to its pixel resolution.
map_resolution() {
    case $1 in
        480) echo 640x480 ;;
        600) echo 800x600 ;;
        720) echo 1280x720 ;;
        768) echo 1024x768 ;;
        1024) echo 1280x1024 ;;
        1080) echo 1920x1080 ;;
        *) return 1 ;;
    esac
}

# Active labels: explicit list, else every subdir of INPUT that holds matrix
# kernel artifacts. Each selected combination is checked for both artifacts below.
if [ -z "$RELEASES" ]; then
    for d in "$INPUT"/*/; do
        [ -d "$d" ] || continue
        label=$(basename "$d")
        [ "$label" = dist ] && continue
        if ls "$d"*/netbsd-warpgfx >/dev/null 2>&1; then
            RELEASES="$RELEASES $label"
        fi
    done
fi
RELEASES=$(echo $RELEASES)
[ -n "$RELEASES" ] || die "no releases with kernel/module combinations found under $INPUT"

mkdir -p "$DIST"
STAGE=$DIST/.stage
rm -rf "$STAGE"
mkdir -p "$STAGE"
trap 'rm -rf "$STAGE"' 0 1 2 15

echo "Publish plan:"
echo "  input:    $INPUT"
echo "  dist:     $DIST"
echo "  releases: $RELEASES"
echo "  formats:  $FORMATS"
echo "  publish:  $([ "$PUBLISH" -eq 1 ] && echo yes || echo 'no (dry run)')"

TOTAL_ASSETS=0
for label in $RELEASES; do
    version=${label#netbsd-}
    note "Packaging $label (version $version)"

    # Decide prerelease flag for this version.
    case $PRERELEASE in
        1) is_pre=1 ;;
        0) is_pre=0 ;;
        auto)
            case $version in
                *RC*|*rc*|current|*.99*|*99.*) is_pre=1 ;;
                *) is_pre=0 ;;
            esac
            ;;
    esac

    ASSETS=''
    for kdir in "$INPUT/$label"/*/; do
        [ -e "$kdir/netbsd-warpgfx" ] || continue
        [ -s "$kdir/netbsd-warpgfx" ] || die "missing or empty kernel in $kdir"
        [ -s "$kdir/wsfb_drv.so.0" ] || die "missing or empty wsfb_drv.so.0 in $kdir"
        combo=$(basename "$kdir")            # e.g. 68060-1080
        cpu=${combo%%-*}
        mode=${combo#*-}
        case $cpu in 68030|68040|68060) ;; *) die "unexpected cpu '$cpu' in $kdir" ;; esac
        res=$(map_resolution "$mode") || die "unknown mode '$mode' in $kdir"

        base=netbsd-amiga-${version}-warpgfx-${DRIVER_VERSION}-${cpu}-${res}
        pkgdir=$STAGE/$base
        rm -rf "$pkgdir"; mkdir -p "$pkgdir"
        cp "$kdir/netbsd-warpgfx" "$pkgdir/$KERNEL_NAME"
        chmod 0644 "$pkgdir/$KERNEL_NAME"
        cp "$kdir/wsfb_drv.so.0" "$pkgdir/wsfb_drv.so.0"
        chmod 0555 "$pkgdir/wsfb_drv.so.0"
        driver_sum=$(sha256_file "$kdir/wsfb_drv.so.0")
        if [ -f "$kdir/BUILD-INFO.txt" ]; then
            sed '/^Driver SHA256:/d' "$kdir/BUILD-INFO.txt" > "$pkgdir/BUILD-INFO.txt"
            printf 'Driver SHA256: %s  wsfb_drv.so.0\n' "$driver_sum" \
                >> "$pkgdir/BUILD-INFO.txt"
        else
            {
                echo "label: $label"
                echo "cpu: $cpu"
                echo "mode: $mode ($res)"
                echo "kernel sha256: $(sha256_file "$kdir/netbsd-warpgfx")"
                echo "Driver SHA256: $driver_sum  wsfb_drv.so.0"
            } > "$pkgdir/BUILD-INFO.txt"
        fi

        for f in $FORMATS; do
            case $f in
                tar.gz)
                    out=$DIST/$base.tar.gz
                    ( cd "$STAGE" && tar -czf "$out" "$base" )
                    ;;
                lha)
                    out=$DIST/$base.lha
                    rm -f "$out"
                    ( cd "$STAGE" && lha a "$out" "$base" >/dev/null )
                    ;;
            esac
            [ -s "$out" ] || die "failed to build $out"
            echo "  built $(basename "$out")"
            ASSETS="$ASSETS $out"
            TOTAL_ASSETS=$((TOTAL_ASSETS + 1))
        done
    done
    [ -n "$ASSETS" ] || die "no kernel + wsfb combinations found for $label under $INPUT/$label"

    # Per-version checksum manifest, also uploaded as an asset.
    sums=$DIST/SHA256SUMS-${version}.txt
    : > "$sums"
    for a in $ASSETS; do
        printf '%s  %s\n' "$(sha256_file "$a")" "$(basename "$a")" >> "$sums"
    done
    ASSETS="$ASSETS $sums"

    tag=${TAG_PREFIX}${version}
    if [ -n "$DRIVER_VERSION" ]; then
        title="WarpGFX $DRIVER_VERSION for NetBSD/amiga $version"
    else
        title="WarpGFX for NetBSD/amiga $version"
    fi
    notes=$STAGE/notes-${version}.md
    {
        echo "WarpGFX accelerated wsdisplay kernel and Xorg wsfb module for NetBSD/amiga $version."
        if [ -n "$DRIVER_VERSION" ]; then
            echo
            echo "WarpGFX driver version: **$DRIVER_VERSION** (query at runtime with"
            echo "\`sysctl hw.warpgfx.version\`; not printed at boot)."
        fi
        echo
        echo "Each archive contains a kernel (\`$KERNEL_NAME\`), the accelerated"
        echo "Xorg module (\`wsfb_drv.so.0\`), and \`BUILD-INFO.txt\`. Pick the"
        echo "archive matching your CPU and desired 16-bit video resolution."
        echo "Keep your current working kernel and wsfb module as fallbacks before"
        echo "installing the replacements."
        echo
        echo "Assets: \`.tar.gz\` and \`.lha\` per CPU (68030/68040/68060) and"
        echo "resolution. SHA-256 sums are in \`$(basename "$sums")\`."
        if [ -f "$ROOT/patches/$label/RELEASE-INFO.txt" ]; then
            echo
            echo '```'
            cat "$ROOT/patches/$label/RELEASE-INFO.txt"
            echo '```'
        fi
    } > "$notes"

    set --
    [ -n "$REPO" ] && set -- "$@" --repo "$REPO"

    if [ "$PUBLISH" -eq 1 ]; then
        if gh release view "$tag" "$@" >/dev/null 2>&1; then
            note "Updating existing release $tag"
            gh release edit "$tag" "$@" --title "$title" --notes-file "$notes" >/dev/null
            # shellcheck disable=SC2086
            gh release upload "$tag" $ASSETS "$@" --clobber
        else
            note "Creating release $tag"
            pre=; [ "$is_pre" -eq 1 ] && pre=--prerelease
            # shellcheck disable=SC2086
            gh release create "$tag" $ASSETS "$@" \
                --title "$title" --notes-file "$notes" $pre
        fi
        echo "  published $tag"
    else
        echo "  [dry run] would publish release: $tag (prerelease=$is_pre)"
        echo "  [dry run] title: $title"
        echo "  [dry run] assets:"
        for a in $ASSETS; do echo "      $(basename "$a")"; done
        echo "  [dry run] gh command (create case):"
        echo "      gh release create $tag <assets> ${REPO:+--repo $REPO} --title \"$title\" --notes-file <notes>$([ "$is_pre" -eq 1 ] && echo ' --prerelease')"
    fi
done

note "Done"
echo "archives in: $DIST"
echo "assets built: $TOTAL_ASSETS"
if [ "$PUBLISH" -eq 0 ]; then
    echo "no uploads performed (dry run); re-run with --publish to create GitHub releases"
fi
