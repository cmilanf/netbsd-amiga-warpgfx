#!/bin/sh
# Build the WarpGFX NetBSD/amiga kernel and accelerated wsfb driver on NetBSD.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG=$ROOT/scripts/canonical-patch-config.sh
SRC_PATCH=$ROOT/patches/canonical/netbsd-src-warpgfx.patch
XSRC_PATCH=$ROOT/patches/canonical/netbsd-xsrc-warpgfx-wsfb-exa.patch
CHECKSUMS=$ROOT/patches/canonical/SHA256.txt

usage() {
    cat <<EOF
usage: $0 [options]

  -c, --cpu CPU             select a 68030, 68040, or 68060 kernel config
  -w, --warpgfx OPTIONS     comma-separated WarpGFX kernel options
  -j, --jobs JOBS           parallel jobs (default: detected CPU count)
      --work-dir DIR        build workspace (default: ~/netbsd-amiga-warpgfx-build)
      --reset-sources       discard cached source edits and reapply current patches
      --only-kernel         build only the kernel using existing cross-tools
      --no-xorg             build cross-tools and kernel only; skip the Xorg build
      --no-diag             do not cross-compile the diag/ diagnostic tools
      --non-reproducible    embed traditional host details in the kernel version
      --config FILE         canonical-patch-config.sh to source
                            (default: repo scripts/canonical-patch-config.sh)
      --src-patch FILE      src patch to apply (default: patches/canonical/netbsd-src-warpgfx.patch)
      --xsrc-patch FILE     xsrc patch to apply (default: patches/canonical/netbsd-xsrc-warpgfx-wsfb-exa.patch)
      --checksums FILE      SHA256 file to verify patches (default: patches/canonical/SHA256.txt)
  -o, --output DIR          artifact directory (default: repository output/)
  -h, --help                show this help

WarpGFX options default to: console,accel,mode=720,no-debug
Supported tokens: console, no-console, accel, no-accel, debug, no-debug,
insecure, no-insecure, and mode=480|600|720|768|1024|1080. "insecure" adds
options INSECURE (securelevel -1) so the diag/ tools can write registers;
use such a kernel only for testing. Example:

  $0 --cpu 68060 --warpgfx console,accel,mode=1080,no-debug -j 2

The diag/ tools are cross-compiled into <output>/diag/ whenever the workspace
destination tree holds the NetBSD/amiga headers and libraries, which a full
build creates and later --only-kernel builds reuse.

The work directory is created on the first run and safely reused on later runs.
Pinned source revisions and patch state are validated before cached objects are
used. If the patches changed, --reset-sources runs git reset --hard and git
clean -fd only in the workspace src/xsrc trees, then reapplies the patches while
preserving cached objects and tools. It discards edits in those source trees.
NetBSD object and tool caches embed absolute paths: do not rename a populated
work directory. To retain a moved cache, keep the old path as a symlink to the
new location and continue passing the old path to --work-dir. Choose a new
--work-dir for a completely clean build. The script does not install files.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

note() {
    printf '\n==> %s\n' "$*"
}

need_arg() {
    [ "$#" -ge 2 ] && [ -n "$2" ] || {
        usage >&2
        exit 2
    }
}

CPU=
WARP_SPEC=
WARP_SPEC_SET=0
JOBS=
WORK_ROOT=${HOME:-/tmp}/netbsd-amiga-warpgfx-build
RESET_SOURCES=0
ONLY_KERNEL=0
SKIP_XORG=0
BUILD_DIAG=1
REPRODUCIBLE=1
OUTPUT=$ROOT/output

while [ "$#" -gt 0 ]; do
    case $1 in
        -c|--cpu)
            need_arg "$@"
            CPU=$2
            shift 2
            ;;
        --cpu=*)
            CPU=${1#*=}
            [ -n "$CPU" ] || die "--cpu requires a value"
            shift
            ;;
        -w|--warpgfx)
            need_arg "$@"
            [ "$WARP_SPEC_SET" -eq 0 ] || die "--warpgfx may be specified only once"
            WARP_SPEC=$2
            WARP_SPEC_SET=1
            shift 2
            ;;
        --warpgfx=*)
            [ "$WARP_SPEC_SET" -eq 0 ] || die "--warpgfx may be specified only once"
            WARP_SPEC=${1#*=}
            WARP_SPEC_SET=1
            shift
            ;;
        -j|--jobs)
            need_arg "$@"
            JOBS=$2
            shift 2
            ;;
        --jobs=*)
            JOBS=${1#*=}
            [ -n "$JOBS" ] || die "--jobs requires a value"
            shift
            ;;
        --work-dir)
            need_arg "$@"
            WORK_ROOT=$2
            shift 2
            ;;
        --work-dir=*)
            WORK_ROOT=${1#*=}
            [ -n "$WORK_ROOT" ] || die "--work-dir requires a value"
            shift
            ;;
        --reset-sources)
            RESET_SOURCES=1
            shift
            ;;
        --only-kernel)
            ONLY_KERNEL=1
            shift
            ;;
        --no-xorg)
            SKIP_XORG=1
            shift
            ;;
        --no-diag)
            BUILD_DIAG=0
            shift
            ;;
        --config)
            need_arg "$@"
            CONFIG=$2
            shift 2
            ;;
        --config=*)
            CONFIG=${1#*=}
            [ -n "$CONFIG" ] || die "--config requires a value"
            shift
            ;;
        --src-patch)
            need_arg "$@"
            SRC_PATCH=$2
            shift 2
            ;;
        --src-patch=*)
            SRC_PATCH=${1#*=}
            [ -n "$SRC_PATCH" ] || die "--src-patch requires a value"
            shift
            ;;
        --xsrc-patch)
            need_arg "$@"
            XSRC_PATCH=$2
            shift 2
            ;;
        --xsrc-patch=*)
            XSRC_PATCH=${1#*=}
            [ -n "$XSRC_PATCH" ] || die "--xsrc-patch requires a value"
            shift
            ;;
        --checksums)
            need_arg "$@"
            CHECKSUMS=$2
            shift 2
            ;;
        --checksums=*)
            CHECKSUMS=${1#*=}
            [ -n "$CHECKSUMS" ] || die "--checksums requires a value"
            shift
            ;;
        --non-reproducible)
            REPRODUCIBLE=0
            shift
            ;;
        -o|--output)
            need_arg "$@"
            OUTPUT=$2
            shift 2
            ;;
        --output=*)
            OUTPUT=${1#*=}
            [ -n "$OUTPUT" ] || die "--output requires a value"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            [ "$#" -eq 0 ] || { usage >&2; exit 2; }
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case $CPU in
    '')
        KERNCONF=WSCONSWARP
        CPU_LABEL='NetBSD/amiga default'
        ;;
    68030)
        KERNCONF=WSCONS030
        CPU_LABEL=68030
        ;;
    68040)
        KERNCONF=WSCONS040
        CPU_LABEL=68040
        ;;
    68060)
        KERNCONF=WSCONS060
        CPU_LABEL=68060
        ;;
    *)
        die "unsupported CPU '$CPU'; use 68030, 68040, or 68060"
        ;;
esac

WARP_CONSOLE=1
WARP_ACCEL=1
WARP_DEBUG=0
WARP_INSECURE=0
WARP_MODE=720
if [ "$WARP_SPEC_SET" -eq 1 ]; then
    [ -n "$WARP_SPEC" ] || die "--warpgfx requires at least one option"
    case $WARP_SPEC in
        ,*|*,|*,,*) die "invalid empty token in --warpgfx '$WARP_SPEC'" ;;
    esac
    WARP_WORDS=$(printf '%s\n' "$WARP_SPEC" | tr ',' ' ')
    for option in $WARP_WORDS; do
        case $option in
            console) WARP_CONSOLE=1 ;;
            no-console) WARP_CONSOLE=0 ;;
            accel) WARP_ACCEL=1 ;;
            no-accel) WARP_ACCEL=0 ;;
            debug) WARP_DEBUG=1 ;;
            no-debug) WARP_DEBUG=0 ;;
            insecure) WARP_INSECURE=1 ;;
            no-insecure) WARP_INSECURE=0 ;;
            mode=480|mode=600|mode=720|mode=768|mode=1024|mode=1080)
                WARP_MODE=${option#mode=}
                ;;
            *)
                die "unsupported WarpGFX option '$option'"
                ;;
        esac
    done
fi

if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)
fi
case $JOBS in
    ''|*[!0-9]*) die "jobs must be a positive integer" ;;
esac
[ "$JOBS" -gt 0 ] || die "jobs must be greater than zero"

case $WORK_ROOT in
    /*) ;;
    *) WORK_ROOT=$PWD/$WORK_ROOT ;;
esac
case $OUTPUT in
    /*) ;;
    *) OUTPUT=$PWD/$OUTPUT ;;
esac
for _ovar in CONFIG SRC_PATCH XSRC_PATCH CHECKSUMS; do
    eval "_oval=\$$_ovar"
    case $_oval in
        /*) ;;
        *) eval "$_ovar=\$PWD/\$_oval" ;;
    esac
done
unset _ovar _oval

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

note "Checking NetBSD host and build dependencies"
[ "$(uname -s)" = NetBSD ] || die "this script must be run on a NetBSD host"
for command in awk cat cc cp date df git install make mkdir mktemp mv rm rmdir sed \
    sha256 sysctl tr uname; do
    need_command "$command"
done
[ -d /usr/include ] || die "NetBSD comp set is missing (/usr/include not found)"
[ -f /usr/include/sys/types.h ] || die "NetBSD C headers are missing; install the comp set"
[ -f "$CONFIG" ] || die "missing $CONFIG"
[ -r "$SRC_PATCH" ] || die "missing or unreadable $SRC_PATCH"
[ -r "$XSRC_PATCH" ] || die "missing or unreadable $XSRC_PATCH"
[ -r "$CHECKSUMS" ] || die "missing or unreadable $CHECKSUMS"

CC_CHECK=$(mktemp -d "${TMPDIR:-/tmp}/warpgfx-cc.XXXXXX") || die "cannot create temporary directory"
trap 'rm -rf "$CC_CHECK"' 0 1 2 15
cat > "$CC_CHECK/check.c" <<'EOF'
int main(void) { return 0; }
EOF
if ! cc -o "$CC_CHECK/check" "$CC_CHECK/check.c" >/dev/null 2>&1; then
    die "the host C compiler cannot build a test program; install a complete NetBSD comp set"
fi
rm -rf "$CC_CHECK"
trap - 0 1 2 15

if command -v pkg_info >/dev/null 2>&1; then
    GIT_PATH=$(command -v git)
    GIT_PACKAGE=$(pkg_info -W "$GIT_PATH" 2>/dev/null || true)
    if [ -n "$GIT_PACKAGE" ]; then
        echo "git package: $GIT_PACKAGE"
    else
        echo "git: $GIT_PATH (not registered in pkgsrc, but usable)"
    fi
fi

verify_checksum() {
    checksum_file=$1
    checksum_name=${checksum_file##*/}
    expected=$(awk -v name="$checksum_name" '$2 == name { print $1 }' "$CHECKSUMS")
    [ -n "$expected" ] || die "no checksum recorded for $checksum_name"
    actual=$(sha256 -q "$checksum_file")
    [ "$actual" = "$expected" ] || die "checksum mismatch for $checksum_name"
}

verify_checksum "$SRC_PATCH"
verify_checksum "$XSRC_PATCH"

# This trusted, checked-in file is the single source of upstream revisions.
# shellcheck source=canonical-patch-config.sh
# shellcheck disable=SC1091
. "$CONFIG"
case $SRC_BASE in ''|*[!0-9a-f]*) die "invalid SRC_BASE in $CONFIG" ;; esac
case $XSRC_BASE in ''|*[!0-9a-f]*) die "invalid XSRC_BASE in $CONFIG" ;; esac
[ "${#SRC_BASE}" -eq 40 ] || die "SRC_BASE must be a full 40-character commit ID"
[ "${#XSRC_BASE}" -eq 40 ] || die "XSRC_BASE must be a full 40-character commit ID"
case $SRC_URL in https://*) ;; *) die "SRC_URL must use HTTPS" ;; esac
case $XSRC_URL in https://*) ;; *) die "XSRC_URL must use HTTPS" ;; esac

[ -d "$WORK_ROOT" ] || [ ! -e "$WORK_ROOT" ] || \
    die "work path exists but is not a directory: $WORK_ROOT"
mkdir -p "$WORK_ROOT" || die "cannot create work directory: $WORK_ROOT"
mkdir -p "$OUTPUT" || die "cannot create output directory: $OUTPUT"

SRC_TREE=$WORK_ROOT/src
XSRC_TREE=$WORK_ROOT/xsrc
OBJ=$WORK_ROOT/obj-amiga
TOOLS=$WORK_ROOT/tools-amiga
DESTDIR=$OBJ/destdir.amiga
if [ "$ONLY_KERNEL" -eq 1 ] && [ ! -x "$TOOLS/bin/nbmake-amiga" ]; then
    die "--only-kernel requires existing cross-tools at $TOOLS; run a full build first"
fi
STATE_FILE=$WORK_ROOT/.warpgfx-build-state
LOCK_DIR=$WORK_ROOT/.build-lock
CLONE_TMP=
VALIDATE_TMP=
STATE_TMP=

cleanup_workspace() {
    cleanup_status=$?
    trap - 0 1 2 15
    if [ -n "$CLONE_TMP" ] && [ -e "$CLONE_TMP" ]; then
        rm -rf "$CLONE_TMP"
    fi
    if [ -n "$VALIDATE_TMP" ] && [ -e "$VALIDATE_TMP" ]; then
        rm -rf "$VALIDATE_TMP"
    fi
    if [ -n "$STATE_TMP" ] && [ -e "$STATE_TMP" ]; then
        rm -f "$STATE_TMP"
    fi
    rmdir "$LOCK_DIR" 2>/dev/null || true
    exit "$cleanup_status"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    die "workspace is locked: $LOCK_DIR (remove it only if no build is running)"
fi
trap cleanup_workspace 0
trap 'exit 1' 1 2 15

SRC_PATCH_SHA=$(sha256 -q "$SRC_PATCH")
XSRC_PATCH_SHA=$(sha256 -q "$XSRC_PATCH")
STATE_CONTENT=$(printf '%s\n' \
    'format=1' \
    "src_base=$SRC_BASE" \
    "xsrc_base=$XSRC_BASE" \
    "src_patch_sha256=$SRC_PATCH_SHA" \
    "xsrc_patch_sha256=$XSRC_PATCH_SHA")

if [ -e "$STATE_FILE" ]; then
    [ -f "$STATE_FILE" ] || die "workspace state is not a regular file: $STATE_FILE"
    ACTUAL_STATE=$(cat "$STATE_FILE")
    if [ "$ACTUAL_STATE" != "$STATE_CONTENT" ] && \
       [ "$RESET_SOURCES" -eq 0 ]; then
        echo "error: workspace sources or patches differ from this release" >&2
        echo "rerun with --reset-sources to discard cached source edits," >&2
        echo "or use a new --work-dir for a completely clean build" >&2
        exit 1
    fi
elif { [ -e "$OBJ" ] || [ -e "$TOOLS" ]; } && \
     { [ ! -d "$SRC_TREE/.git" ] || [ ! -d "$XSRC_TREE/.git" ]; } && \
     [ "$RESET_SOURCES" -eq 0 ]; then
    die "workspace has cached objects but no complete validated source trees; use --reset-sources or a new --work-dir"
fi

AVAILABLE_KB=$(df -Pk "$WORK_ROOT" | awk 'NR == 2 { print $4 }')
case $AVAILABLE_KB in
    ''|*[!0-9]*) ;;
    *)
        if [ "$AVAILABLE_KB" -lt 12582912 ]; then
            echo "warning: less than 12 GiB is available for the build" >&2
        fi
        ;;
esac

prepare_tree() {
    tree_name=$1
    tree_url=$2
    tree_revision=$3
    tree_path=$4

    if [ ! -e "$tree_path" ]; then
        note "Fetching pinned $tree_name commit $tree_revision"
        CLONE_TMP=${tree_path}.tmp.$$
        [ ! -e "$CLONE_TMP" ] || die "temporary clone path already exists: $CLONE_TMP"
        mkdir "$CLONE_TMP"
        git -C "$CLONE_TMP" init -q
        git -C "$CLONE_TMP" remote add origin "$tree_url"
        git -C "$CLONE_TMP" fetch --depth=1 origin "$tree_revision"
        git -C "$CLONE_TMP" checkout -q --detach FETCH_HEAD
        mv "$CLONE_TMP" "$tree_path"
        CLONE_TMP=
    else
        note "Reusing cached $tree_name tree"
    fi

    [ -d "$tree_path/.git" ] || die "$tree_name tree is not a Git worktree: $tree_path"
    tree_inside=$(git -C "$tree_path" rev-parse --is-inside-work-tree 2>/dev/null || true)
    [ "$tree_inside" = true ] || die "$tree_name tree is not a usable Git worktree: $tree_path"
    tree_origin=$(git -C "$tree_path" remote get-url origin 2>/dev/null || true)
    [ "$tree_origin" = "$tree_url" ] || \
        die "$tree_name origin is '$tree_origin', expected '$tree_url'"
    git -C "$tree_path" cat-file -e "$tree_revision^{commit}" 2>/dev/null || \
        die "$tree_name tree does not contain pinned commit $tree_revision"
    tree_actual=$(git -C "$tree_path" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)
    [ "$tree_actual" = "$tree_revision" ] || \
        die "$tree_name checkout is '$tree_actual', expected '$tree_revision'"
}

validate_patch_state() {
    patch_name=$1
    patch_tree=$2
    patch_revision=$3
    patch_file=$4
    allow_kernel_configs=$5

    VALIDATE_TMP=$(mktemp -d "$WORK_ROOT/.validate.XXXXXX") || \
        die "cannot create validation directory"
    expected_index=$VALIDATE_TMP/expected.index
    actual_index=$VALIDATE_TMP/actual.index

    GIT_INDEX_FILE=$expected_index git -C "$patch_tree" read-tree "$patch_revision"
    GIT_INDEX_FILE=$expected_index git -C "$patch_tree" apply \
        --cached --whitespace=nowarn "$patch_file"
    expected_tree=$(GIT_INDEX_FILE=$expected_index git -C "$patch_tree" write-tree)

    GIT_INDEX_FILE=$actual_index git -C "$patch_tree" read-tree "$patch_revision"
    GIT_INDEX_FILE=$actual_index git -C "$patch_tree" add -A
    if [ "$allow_kernel_configs" -eq 1 ]; then
        GIT_INDEX_FILE=$actual_index git -C "$patch_tree" reset -q "$patch_revision" -- \
            sys/arch/amiga/conf/WSCONSWARP sys/arch/amiga/conf/WSCONS030 \
            sys/arch/amiga/conf/WSCONS040 sys/arch/amiga/conf/WSCONS060
    fi
    actual_tree=$(GIT_INDEX_FILE=$actual_index git -C "$patch_tree" write-tree)
    base_tree=$(git -C "$patch_tree" rev-parse "$patch_revision^{tree}")

    case $actual_tree in
        "$base_tree")
            note "Applying $patch_name patch"
            git -C "$patch_tree" add -A
            if [ "$allow_kernel_configs" -eq 1 ]; then
                git -C "$patch_tree" reset -q "$patch_revision" -- \
                    sys/arch/amiga/conf/WSCONSWARP sys/arch/amiga/conf/WSCONS030 \
                    sys/arch/amiga/conf/WSCONS040 sys/arch/amiga/conf/WSCONS060
            fi
            git -C "$patch_tree" apply --index --whitespace=nowarn "$patch_file"
            ;;
        "$expected_tree")
            note "Reusing validated $patch_name patch state"
            # Normalize workspaces made by older versions, which left the patch unstaged.
            git -C "$patch_tree" add -A
            if [ "$allow_kernel_configs" -eq 1 ]; then
                git -C "$patch_tree" reset -q "$patch_revision" -- \
                    sys/arch/amiga/conf/WSCONSWARP sys/arch/amiga/conf/WSCONS030 \
                    sys/arch/amiga/conf/WSCONS040 sys/arch/amiga/conf/WSCONS060
            fi
            ;;
        *)
            echo "error: $patch_name tree has unexpected source changes:" >&2
            GIT_INDEX_FILE=$actual_index git -C "$patch_tree" diff \
                --cached --name-status "$patch_revision" >&2 || true
            rm -rf "$VALIDATE_TMP"
            VALIDATE_TMP=
            die "restore the listed paths, use --reset-sources to discard cached source edits, or use a new --work-dir"
            ;;
    esac

    normalized_tree=$(git -C "$patch_tree" write-tree)
    [ "$normalized_tree" = "$expected_tree" ] || \
        die "$patch_name index does not match the release patch"
    git -C "$patch_tree" diff --quiet || \
        die "$patch_name worktree changed while it was being validated"
    rm -rf "$VALIDATE_TMP"
    VALIDATE_TMP=
}

prepare_tree src "$SRC_URL" "$SRC_BASE" "$SRC_TREE"
prepare_tree xsrc "$XSRC_URL" "$XSRC_BASE" "$XSRC_TREE"

if [ "$RESET_SOURCES" -eq 1 ]; then
    note "Resetting cached source trees to their pinned revisions"
    echo "Discarding tracked and untracked changes under:"
    echo "  $SRC_TREE"
    echo "  $XSRC_TREE"
    git -C "$SRC_TREE" reset --hard "$SRC_BASE"
    git -C "$SRC_TREE" clean -fd
    git -C "$XSRC_TREE" reset --hard "$XSRC_BASE"
    git -C "$XSRC_TREE" clean -fd
    rm -f "$STATE_FILE"
fi

validate_patch_state src "$SRC_TREE" "$SRC_BASE" "$SRC_PATCH" 1
validate_patch_state xsrc "$XSRC_TREE" "$XSRC_BASE" "$XSRC_PATCH" 0

if [ ! -e "$STATE_FILE" ]; then
    STATE_TMP=$WORK_ROOT/.warpgfx-build-state.tmp.$$
    printf '%s\n' "$STATE_CONTENT" > "$STATE_TMP"
    mv "$STATE_TMP" "$STATE_FILE"
    STATE_TMP=
fi

note "Generating kernel configuration $KERNCONF"
BASE_CONFIG=$SRC_TREE/sys/arch/amiga/conf/WSCONS
KERNEL_CONFIG=$SRC_TREE/sys/arch/amiga/conf/$KERNCONF
[ -f "$BASE_CONFIG" ] || die "patched WSCONS configuration was not created"
KERNEL_CONFIG_NEW=$WORK_ROOT/.kernel-config.$$
{
    printf 'include\t"arch/amiga/conf/WSCONS"\n'

    case $CPU in
        68030)
            cat <<'EOF'

# Generate code exclusively for the Motorola 68030.
no options	M68020
no options	M68040
no options	M68060

# The 68060 software support package requires M68060.
no options	M060SP

# FPSP is the 68040-specific FPU support package; it is unnecessary here.
# FPU_EMULATE is inherited from GENERIC and intentionally kept: a bare 68030
# has no on-chip FPU, so a machine lacking a 68881/68882 relies on emulation.
no options	FPSP
EOF
            ;;
        68040)
            cat <<'EOF'

# Generate code exclusively for the Motorola 68040.
no options	M68020
no options	M68030
no options	M68060

# The 68060 software support package requires M68060.
no options	M060SP

# Keep FPSP (inherited from GENERIC): the 68040 FPU implements only part of
# the instruction set in hardware and traps the rest, which FPSP emulates.
# The 68040 has an on-chip FPU, so full software FPU emulation is unnecessary.
no options	FPU_EMULATE
EOF
            ;;
        68060)
            cat <<'EOF'

# Generate code exclusively for the Motorola 68060.
no options	M68020
no options	M68030
no options	M68040

# 68040-only and generic FPU support are unnecessary.
no options	FPSP
no options	FPU_EMULATE
EOF
            ;;
    esac

    cat <<EOF

# WarpGFX options generated by scripts/build-netbsd-amiga.sh
no options	WARPGFX_CONSOLE
no options	WARPGFX_ACCEL
no options	WARPGFX_MODE
no options	WARPGFX_DEBUG
EOF
    if [ "$WARP_CONSOLE" -eq 1 ]; then
        printf 'options\t\tWARPGFX_CONSOLE\n'
    fi
    if [ "$WARP_ACCEL" -eq 1 ]; then
        printf 'options\t\tWARPGFX_ACCEL\n'
    fi
    printf 'options\t\tWARPGFX_MODE=%s\n' "$WARP_MODE"
    if [ "$WARP_DEBUG" -eq 1 ]; then
        printf 'options\t\tWARPGFX_DEBUG\n'
    fi
    if [ "$WARP_INSECURE" -eq 1 ]; then
        printf '\n# Test kernel: securelevel -1 so root can write /dev/mem.\n'
        printf 'options\t\tINSECURE\n'
    fi
} > "$KERNEL_CONFIG_NEW"
if [ -f "$KERNEL_CONFIG" ] && \
    [ "$(sha256 -q "$KERNEL_CONFIG")" = "$(sha256 -q "$KERNEL_CONFIG_NEW")" ]; then
    rm -f "$KERNEL_CONFIG_NEW"
else
    mv "$KERNEL_CONFIG_NEW" "$KERNEL_CONFIG"
fi

if [ "$ONLY_KERNEL" -eq 0 ] && [ "$SKIP_XORG" -eq 0 ]; then
    BUILD_XORG=1
else
    BUILD_XORG=0
fi
if [ "$ONLY_KERNEL" -eq 1 ]; then
    BUILD_SCOPE='kernel only (reusing cross-tools)'
elif [ "$SKIP_XORG" -eq 1 ]; then
    BUILD_SCOPE='cross-tools and kernel (Xorg skipped)'
else
    BUILD_SCOPE='kernel and Xorg driver'
fi
if [ "$REPRODUCIBLE" -eq 1 ]; then
    KERNEL_VERSION_MODE='reproducible (host details omitted)'
else
    KERNEL_VERSION_MODE='traditional (user, host, time, and path embedded)'
fi

cat <<EOF
Build settings:
  target:       $BUILD_SCOPE
  CPU:          $CPU_LABEL
  kernel:       $KERNCONF
  version info: $KERNEL_VERSION_MODE
  Warp console: $WARP_CONSOLE
  acceleration: $WARP_ACCEL
  debug:        $WARP_DEBUG
  insecure:     $WARP_INSECURE
  video mode:   $WARP_MODE
  jobs:         $JOBS
  workspace:    $WORK_ROOT
  output:       $OUTPUT
EOF

if [ "$ONLY_KERNEL" -eq 1 ]; then
    note "Reusing existing NetBSD cross-tools for amiga"
else
    note "Building NetBSD cross-tools for amiga"
    (
        cd "$SRC_TREE"
        ./build.sh -U -u -m amiga -O "$OBJ" -T "$TOOLS" -j"$JOBS" tools
    )
    [ -x "$TOOLS/bin/nbmake-amiga" ] || die "tools build did not produce nbmake-amiga"
fi

note "Building NetBSD/amiga kernel $KERNCONF"
KERNEL_COMPILE_DIR=$OBJ/sys/arch/amiga/compile/$KERNCONF
rm -f "$KERNEL_COMPILE_DIR/vers.c" "$KERNEL_COMPILE_DIR/vers.o"
(
    cd "$SRC_TREE"
    if [ "$REPRODUCIBLE" -eq 1 ]; then
        ./build.sh -U -u -m amiga -O "$OBJ" -T "$TOOLS" \
            -V MKREPRO=yes -j"$JOBS" "kernel=$KERNCONF"
    else
        ./build.sh -U -u -m amiga -O "$OBJ" -T "$TOOLS" \
            -j"$JOBS" "kernel=$KERNCONF"
    fi
)

if [ "$BUILD_XORG" -eq 1 ]; then
    note "Building the NetBSD Xorg distribution and accelerated wsfb driver"
    (
        cd "$SRC_TREE"
        ./build.sh -U -m amiga -O "$OBJ" -T "$TOOLS" -D "$DESTDIR" \
            -X "$XSRC_TREE" -x -u -j"$JOBS" distribution
    )
fi

KERNEL_ARTIFACT=$OBJ/sys/arch/amiga/compile/$KERNCONF/netbsd
[ -s "$KERNEL_ARTIFACT" ] || die "kernel artifact not found: $KERNEL_ARTIFACT"

KERNEL_OUTPUT=$OUTPUT/netbsd-warpgfx
install -m 0444 "$KERNEL_ARTIFACT" "$KERNEL_OUTPUT"

if [ "$BUILD_XORG" -eq 1 ]; then
    DRIVER_ARTIFACT=$DESTDIR/usr/X11R7/lib/modules/drivers/wsfb_drv.so.0
    [ -s "$DRIVER_ARTIFACT" ] || die "Xorg driver artifact not found: $DRIVER_ARTIFACT"
    DRIVER_OUTPUT=$OUTPUT/wsfb_drv.so.0
    install -m 0555 "$DRIVER_ARTIFACT" "$DRIVER_OUTPUT"
fi

DIAG_SRC=$ROOT/diag
DIAG_OUTPUT=$OUTPUT/diag
DIAG_CC=$TOOLS/bin/m68k--netbsdelf-gcc
DIAG_BUILT=0
DIAG_PROGS=
if [ "$BUILD_DIAG" -eq 1 ]; then
    [ -f "$DIAG_SRC/Makefile" ] || die "missing $DIAG_SRC/Makefile"
    DIAG_PROGS=$(sed -n 's/^PROGS=[[:space:]]*//p' "$DIAG_SRC/Makefile")
    [ -n "$DIAG_PROGS" ] || die "no PROGS list in $DIAG_SRC/Makefile"
    if [ -x "$DIAG_CC" ] && [ -f "$DESTDIR/usr/include/stdio.h" ] && \
       [ -f "$DESTDIR/usr/include/dev/wscons/wsconsio.h" ] && \
       { [ -f "$DESTDIR/usr/lib/libc.so" ] || [ -f "$DESTDIR/usr/lib/libc.a" ]; }; then
        note "Cross-compiling the WarpGFX diagnostic tools"
        mkdir -p "$DIAG_OUTPUT"
        for prog in $DIAG_PROGS; do
            "$DIAG_CC" --sysroot="$DESTDIR" -O2 -Wall -Wextra -Werror \
                -o "$DIAG_OUTPUT/$prog.tmp" "$DIAG_SRC/$prog.c" || \
                die "failed to build diagnostic tool $prog"
            install -m 0555 "$DIAG_OUTPUT/$prog.tmp" "$DIAG_OUTPUT/$prog"
            rm -f "$DIAG_OUTPUT/$prog.tmp"
        done
        for script in "$DIAG_SRC"/warptest-*.sh; do
            case ${script##*/} in
                warptest-common.sh) install -m 0444 "$script" "$DIAG_OUTPUT/" ;;
                *) install -m 0555 "$script" "$DIAG_OUTPUT/" ;;
            esac
        done
        install -m 0444 "$DIAG_SRC/README.md" "$DIAG_OUTPUT/README.md"
        DIAG_BUILT=1
    else
        note "Skipping the diagnostic tools: $DESTDIR has no NetBSD/amiga headers and libraries yet (run a full build)"
    fi
fi

BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
KERNEL_SHA256=$(sha256 -q "$KERNEL_OUTPUT")
{
    cat <<EOF
Build time: $BUILD_TIME
Build target: $BUILD_SCOPE
src commit: $SRC_BASE
xsrc commit: $XSRC_BASE
CPU: $CPU_LABEL
Kernel config: $KERNCONF
Kernel version metadata: $KERNEL_VERSION_MODE
WARPGFX_CONSOLE: $WARP_CONSOLE
WARPGFX_ACCEL: $WARP_ACCEL
WARPGFX_DEBUG: $WARP_DEBUG
WARPGFX_MODE: $WARP_MODE
INSECURE: $WARP_INSECURE
Kernel SHA256: $KERNEL_SHA256  ${KERNEL_OUTPUT##*/}
EOF
    if [ "$DIAG_BUILT" -eq 1 ]; then
        for prog in $DIAG_PROGS; do
            echo "Diag SHA256: $(sha256 -q "$DIAG_OUTPUT/$prog")  diag/$prog"
        done
    fi
    if [ "$BUILD_XORG" -eq 1 ]; then
        DRIVER_SHA256=$(sha256 -q "$DRIVER_OUTPUT")
        echo "Driver SHA256: $DRIVER_SHA256  ${DRIVER_OUTPUT##*/}"
    fi
} > "$OUTPUT/BUILD-INFO.txt"

note "Build completed"
echo "Artifacts:"
echo "  $KERNEL_OUTPUT"
if [ "$BUILD_XORG" -eq 1 ]; then
    echo "  $DRIVER_OUTPUT"
fi
if [ "$DIAG_BUILT" -eq 1 ]; then
    echo "  $DIAG_OUTPUT/ (diagnostic tools, see README.md there)"
fi
echo "  $OUTPUT/BUILD-INFO.txt"
cat <<EOF

Next steps (not performed by this script):

1. Keep your current working kernel and boot method as a fallback. Copy
   ${KERNEL_OUTPUT##*/} to the location used by your Amiga bootblock or
   AmigaOS loadbsd setup, then test it without removing the known-good kernel.
EOF

if [ "$BUILD_XORG" -eq 0 ]; then
    if [ "$ONLY_KERNEL" -eq 1 ]; then
        cat <<EOF

The Xorg distribution and wsfb driver were skipped by --only-kernel. Any
existing wsfb_drv.so.0 in the output directory was left unchanged.
EOF
    else
        cat <<EOF

The Xorg distribution and wsfb driver were skipped by --no-xorg. Cross-tools
and the kernel were built. Any existing wsfb_drv.so.0 in the output directory
was left unchanged.
EOF
    fi
else
    cat <<EOF

2. Stop X, back up the installed wsfb module, and install the new one as root:

   cp /usr/X11R7/lib/modules/drivers/wsfb_drv.so.0 \\
      /usr/X11R7/lib/modules/drivers/wsfb_drv.so.0.backup
   install -m 0555 "$DRIVER_OUTPUT" \\
      /usr/X11R7/lib/modules/drivers/wsfb_drv.so.0

3. Configure /etc/X11/xorg.conf with Driver "wsfb", Device "/dev/ttyE0",
   ShadowFB "false", Accel "true", and HWCursor "false". After starting X,
   verify "Using wsdisplay EXA fill/copy acceleration" in
   /var/log/Xorg.0.log and "console/wsfb acceleration" in dmesg.

If X acceleration causes a regression, set Accel "false" to use the software
fallback without rebuilding the kernel or module.
EOF
fi
