#!/bin/sh
# Copyright (c) 2026, Carlos Milán Figueredo
# SPDX-License-Identifier: BSD-2-Clause
# Developed with assistance from OpenAI GPT-5.6-Sol, Kiro, and
# Anthropic Claude Opus 5.5.

set -eu

usage()
{
    cat <<'EOF'
Usage: install.sh [--destdir DIR] [--prefix DIR] [--dry-run] [--force]

Install the optional WarpGFX wscons fonts and reproducibility bundle.
The script never edits /etc/wscons.conf or /etc/ttys.

Options:
  --destdir DIR  Staging root (default: $DESTDIR or empty)
  --prefix DIR   Absolute install prefix (default: $PREFIX or /usr/local)
  --dry-run      Print actions without writing
  --force        Replace a different existing regular file
  -h, --help     Show this help
EOF
}

die()
{
    echo "install.sh: $*" >&2
    exit 1
}

DESTDIR=${DESTDIR-}
PREFIX=${PREFIX-/usr/local}
DRY_RUN=0
FORCE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --destdir)
            [ "$#" -ge 2 ] || die "--destdir requires an argument"
            DESTDIR=$2
            shift 2
            ;;
        --destdir=*)
            DESTDIR=${1#*=}
            shift
            ;;
        --prefix)
            [ "$#" -ge 2 ] || die "--prefix requires an argument"
            PREFIX=$2
            shift 2
            ;;
        --prefix=*)
            PREFIX=${1#*=}
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

normalize_path()
{
    normalized=$1
    while [ "$normalized" != / ] && [ "${normalized%/}" != "$normalized" ]; do
        normalized=${normalized%/}
    done
    echo "$normalized"
}

validate_absolute_path()
{
    path=$1
    label=$2
    case "$path" in
        /*) ;;
        *) die "$label must be an absolute path: $path" ;;
    esac
    remainder=${path#/}
    while [ -n "$remainder" ]; do
        component=${remainder%%/*}
        case "$component" in
            ""|.|..) die "$label contains an unsafe component: $path" ;;
        esac
        if [ "$remainder" = "$component" ]; then
            remainder=
        else
            remainder=${remainder#*/}
        fi
    done
}

assert_no_symlink_components()
{
    path=$1
    remainder=${path#/}
    current=
    while [ -n "$remainder" ]; do
        component=${remainder%%/*}
        current=$current/$component
        [ ! -L "$current" ] ||
            die "refusing path with symlink component: $current"
        if [ "$remainder" = "$component" ]; then
            remainder=
        else
            remainder=${remainder#*/}
        fi
    done
}

PREFIX=$(normalize_path "$PREFIX")
DESTDIR=$(normalize_path "$DESTDIR")
validate_absolute_path "$PREFIX" prefix
if [ -n "$DESTDIR" ]; then
    validate_absolute_path "$DESTDIR" destdir
fi
# DESTDIR=/ is equivalent to no staging root; avoid producing //etc and similar.
if [ "$DESTDIR" = / ]; then
    DESTDIR=
fi
INSTALL_ROOT=${DESTDIR}${PREFIX}
validate_absolute_path "$INSTALL_ROOT" "combined install root"
case "$INSTALL_ROOT" in
    /etc|/etc/*) die "refusing to install under /etc: $INSTALL_ROOT" ;;
esac
assert_no_symlink_components "$INSTALL_ROOT"

TEMPORARY_FILE=
cleanup()
{
    if [ -n "$TEMPORARY_FILE" ]; then
        rm -f "$TEMPORARY_FILE"
        TEMPORARY_FILE=
    fi
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
FONT_DIR=$INSTALL_ROOT/share/wscons/fonts
DOC_DIR=$INSTALL_ROOT/share/doc/warpgfx-wscons-fonts
DOC_ARTIFACT_DIR=$DOC_DIR/artifacts
DOC_SOURCE_DIR=$DOC_DIR/sources
DOC_LICENSE_DIR=$DOC_DIR/licenses

preflight_directory()
{
    directory=$1
    assert_no_symlink_components "$directory"
    if [ -e "$directory" ]; then
        [ -d "$directory" ] ||
            die "destination directory is not a directory: $directory"
    fi
}

preflight_file()
{
    source_file=$1
    target_file=$2
    target_directory=${target_file%/*}

    [ -f "$source_file" ] || die "missing source file: $source_file"
    [ ! -L "$source_file" ] || die "refusing symlink source: $source_file"
    assert_no_symlink_components "$target_directory"
    [ ! -L "$target_file" ] ||
        die "refusing symlink destination: $target_file"
    if [ -e "$target_file" ]; then
        [ -f "$target_file" ] ||
            die "refusing non-regular destination: $target_file"
        if ! cmp "$source_file" "$target_file" >/dev/null 2>&1; then
            [ "$FORCE" -eq 1 ] || die \
                "refusing to replace different file: $target_file (use --force)"
        fi
    fi
}

make_directory()
{
    directory=$1
    preflight_directory "$directory"
    if [ -d "$directory" ]; then
        return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "create directory $directory"
    else
        install -d -m 0755 "$directory"
        assert_no_symlink_components "$directory"
    fi
}

install_file()
{
    source_file=$1
    target_file=$2
    mode=$3

    # Repeat target checks to defend against changes after the global preflight.
    preflight_file "$source_file" "$target_file"
    if [ -e "$target_file" ] &&
        cmp "$source_file" "$target_file" >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "already installed; set mode $mode: $target_file"
        else
            chmod "$mode" "$target_file"
            echo "already installed; mode normalized: $target_file"
        fi
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "install $source_file -> $target_file (mode $mode)"
        return
    fi

    TEMPORARY_FILE=$(mktemp "${target_file}.tmp.XXXXXX") ||
        die "cannot create temporary file beside $target_file"
    if ! install -m "$mode" "$source_file" "$TEMPORARY_FILE"; then
        cleanup
        die "cannot prepare $target_file"
    fi
    [ ! -L "$target_file" ] || {
        cleanup
        die "destination became a symlink: $target_file"
    }
    if [ -e "$target_file" ]; then
        [ -f "$target_file" ] || {
            cleanup
            die "destination became non-regular: $target_file"
        }
    fi
    # The temporary file is in the target directory, so this is one rename(2).
    if ! mv -f "$TEMPORARY_FILE" "$target_file"; then
        cleanup
        die "cannot install $target_file"
    fi
    TEMPORARY_FILE=
    echo "installed: $target_file"
}

process_directories()
{
    action=$1
    "$action" "$FONT_DIR"
    "$action" "$DOC_DIR"
    "$action" "$DOC_ARTIFACT_DIR"
    "$action" "$DOC_SOURCE_DIR"
    "$action" "$DOC_LICENSE_DIR"
}

process_files()
{
    action=$1
    for file in WarpConsole-24x40.wsf WarpConsole-16x30.wsf \
        WarpConsole-VGA-CP437-Raw-24x40.wsf \
        WarpConsole-VGA-CP437-Raw-16x28.wsf \
        WarpConsole-VGA-CP437-Raw-8x16.wsf; do
        "$action" "$SCRIPT_DIR/artifacts/$file" "$FONT_DIR/$file" 0444
        "$action" "$SCRIPT_DIR/artifacts/$file" \
            "$DOC_ARTIFACT_DIR/$file" 0444
    done
    for file in README.md SHA256.txt wscons-1920x1080.conf.example \
        wscons-1280x720.conf.example wscons-640x480.conf.example; do
        "$action" "$SCRIPT_DIR/$file" "$DOC_DIR/$file" 0444
    done
    for file in generate_scaled_wsf.py generate_vga_cp437_wsf.py validate.py \
        install.sh; do
        "$action" "$SCRIPT_DIR/$file" "$DOC_DIR/$file" 0555
    done
    for file in ter-132n.wsf PCFace-Oldschool-VGA-8x16-fontlist.js; do
        "$action" "$SCRIPT_DIR/sources/$file" \
            "$DOC_SOURCE_DIR/$file" 0444
    done
    for file in OFL-1.1.txt CC-BY-SA-4.0.txt \
        TERMINUS-FONT-NOTICE.md OLDSCHOOL-VGA-FONT-NOTICE.md; do
        "$action" "$SCRIPT_DIR/licenses/$file" \
            "$DOC_LICENSE_DIR/$file" 0444
    done
}

# Preflight every source, path, target, and collision before the first write.
process_directories preflight_directory
process_files preflight_file

process_directories make_directory
process_files install_file

cat <<EOF
Fonts installed under: $FONT_DIR
Reproducibility bundle installed under: $DOC_DIR
No system configuration was changed.
Review the wscons-<resolution>.conf.example in $DOC_DIR that matches your
WarpGFX kernel's mode and merge only the desired lines manually.
EOF
if [ "$PREFIX" != /usr/local ]; then
    echo "Replace /usr/local in the example with your prefix: $PREFIX"
fi
