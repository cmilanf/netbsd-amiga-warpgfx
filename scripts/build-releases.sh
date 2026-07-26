#!/bin/sh
# Build the WarpGFX release matrix: every active release in
# scripts/create-release-patches.conf x every CPU x every video mode. Runs on a
# NetBSD host because it drives scripts/build-netbsd-amiga.sh, which rejects
# other hosts.
#
# Per release the first successful combination is a full kernel + Xorg build.
# Later combinations reuse its accelerated wsfb module and build only the kernel
# with --only-kernel. If a full build fails, the next combination retries a full
# build. Failures are recorded and the matrix continues; the script exits
# non-zero if any combination failed.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST=$ROOT/scripts/create-release-patches.conf
BUILD=$ROOT/scripts/build-netbsd-amiga.sh
[ -f "$MANIFEST" ] || { echo "missing $MANIFEST" >&2; exit 1; }
[ -x "$BUILD" ] || { echo "missing or non-executable $BUILD" >&2; exit 1; }

CPUS='68030 68040 68060'
MODES='720 1080'
RELEASES=
JOBS=
WORK_ROOT=${HOME:-/tmp}/warpgfx-release-build
OUTPUT=$ROOT/output
DRY_RUN=0
RESET_SOURCES=0

usage() {
    cat >&2 <<EOF
usage: $0 [options]

      --releases "L1 L2"   space-separated labels
                            (default: all active in create-release-patches.conf)
      --cpus "C1 C2"       CPU list (default: $CPUS)
      --modes "M1 M2"      WARPGFX_MODE list (default: $MODES)
  -j, --jobs N             parallel build jobs (default: build script's default)
      --work-dir DIR       release workspace root (default: ~/warpgfx-release-build)
  -o, --output DIR         release artifact root (default: repo output/)
      --reset-sources      on the first combo per release, discard cached source
                           edits and reapply the current patch (use after the
                           patch changed; preserves cached tools and objects)
  -n, --dry-run            print the planned build commands and exit
  -h, --help               show this help

Each release gets its own workspace at <work-dir>/<label> (shared across that
release's combinations). The first successful combination per release builds
the kernel and accelerated Xorg wsfb module; later combinations use
--only-kernel and reuse that module. Each combination's artifacts go to
<output>/<label>/<cpu>-<mode>/. A release summary with kernel and driver SHA-256
sums is written to <output>/RELEASE-SUMMARY.txt.
EOF
}

need_arg() { [ "$#" -ge 2 ] && [ -n "$2" ] || { usage; exit 2; }; }

while [ "$#" -gt 0 ]; do
    case $1 in
        --releases) need_arg "$@"; RELEASES=$2; shift 2 ;;
        --cpus) need_arg "$@"; CPUS=$2; shift 2 ;;
        --modes) need_arg "$@"; MODES=$2; shift 2 ;;
        -j|--jobs) need_arg "$@"; JOBS=$2; shift 2 ;;
        --work-dir) need_arg "$@"; WORK_ROOT=$2; shift 2 ;;
        -o|--output) need_arg "$@"; OUTPUT=$2; shift 2 ;;
        --reset-sources) RESET_SOURCES=1; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

case $WORK_ROOT in /*) ;; *) WORK_ROOT=$PWD/$WORK_ROOT ;; esac
case $OUTPUT in /*) ;; *) OUTPUT=$PWD/$OUTPUT ;; esac

# Active labels from the manifest (skip comments/blank lines).
ACTIVE_LABELS=$(awk -F'|' '/^[[:space:]]*#/ {next} /^[[:space:]]*$/ {next} {print $1}' "$MANIFEST")
ACTIVE_LABELS=$(echo $ACTIVE_LABELS)
[ -n "$ACTIVE_LABELS" ] || { echo "no active releases in $MANIFEST" >&2; exit 1; }
if [ -z "$RELEASES" ]; then
    RELEASES=$ACTIVE_LABELS
fi

sha256_file() {
    if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | sed 's/[[:space:]].*//'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | sed 's/[[:space:]].*//'
    else echo "sha256, shasum, or sha256sum is required" >&2; return 1; fi
}

# Validate requested labels exist in the manifest and have generated patches.
for label in $RELEASES; do
    found=0
    for active in $ACTIVE_LABELS; do [ "$label" = "$active" ] && found=1; done
    [ "$found" -eq 1 ] || { echo "release not active in manifest: $label" >&2; exit 1; }
    rel_dir=$ROOT/patches/$label
    for f in canonical-patch-config.sh netbsd-src-warpgfx.patch \
        netbsd-xsrc-warpgfx-wsfb-exa.patch SHA256.txt; do
        [ -r "$rel_dir/$f" ] || {
            echo "missing $rel_dir/$f (run create-release-patches.sh)" >&2
            exit 1
        }
    done
done

TOTAL=0
for label in $RELEASES; do
    for cpu in $CPUS; do
        for mode in $MODES; do TOTAL=$((TOTAL + 1)); done
    done
done

echo "Matrix plan:"
echo "  releases: $RELEASES"
echo "  cpus:     $CPUS"
echo "  modes:    $MODES"
echo "  combos:   $TOTAL"
echo "  work-dir: $WORK_ROOT"
echo "  output:   $OUTPUT"
echo

mkdir -p "$OUTPUT"
SUMMARY=$OUTPUT/RELEASE-SUMMARY.txt
if [ "$DRY_RUN" -eq 0 ]; then
    {
        echo "WarpGFX kernel + accelerated wsfb build matrix"
        echo "started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "host:    $(uname -a)"
        echo
    } > "$SUMMARY"
fi

FAILED=
DONE=0
for label in $RELEASES; do
    rel_dir=$ROOT/patches/$label
    ws=$WORK_ROOT/$label
    reset_pending=$RESET_SOURCES
    module_ready=0
    release_driver=
    for cpu in $CPUS; do
        for mode in $MODES; do
            DONE=$((DONE + 1))
            out=$OUTPUT/$label/$cpu-$mode
            log=$OUTPUT/$label/build-$cpu-$mode.log
            if [ "$module_ready" -eq 1 ]; then
                scope_flag=--only-kernel
                scope_name=--only-kernel
            else
                scope_flag=
                scope_name='full build'
            fi
            set -- "$BUILD" \
                --config "$rel_dir/canonical-patch-config.sh" \
                --src-patch "$rel_dir/netbsd-src-warpgfx.patch" \
                --xsrc-patch "$rel_dir/netbsd-xsrc-warpgfx-wsfb-exa.patch" \
                --checksums "$rel_dir/SHA256.txt" \
                --cpu "$cpu" \
                --warpgfx "console,accel,mode=$mode,no-debug" \
                --work-dir "$ws" \
                --output "$out"
            [ -n "$scope_flag" ] && set -- "$@" "$scope_flag"
            [ -n "$JOBS" ] && set -- "$@" --jobs "$JOBS"
            if [ "$reset_pending" -eq 1 ]; then
                set -- "$@" --reset-sources
                reset_pending=0
            fi

            echo "[$DONE/$TOTAL] $label cpu=$cpu mode=$mode ($scope_name)"
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "    $*"
                if [ "$module_ready" -eq 0 ]; then
                    module_ready=1
                    release_driver=$out/wsfb_drv.so.0
                fi
                continue
            fi
            mkdir -p "$out" "$OUTPUT/$label"
            if "$@" > "$log" 2>&1; then
                kernel=$out/netbsd-warpgfx
                driver=$out/wsfb_drv.so.0
                copy_error=
                reused_module=0
                if [ "$module_ready" -eq 1 ]; then
                    reused_module=1
                    if ! install -m 0555 "$release_driver" "$driver"; then
                        copy_error='could not install reused driver artifact'
                    fi
                fi
                if [ -z "$copy_error" ] && [ -s "$kernel" ] && [ -s "$driver" ]; then
                    kernel_sum=$(sha256_file "$kernel")
                    driver_sum=$(sha256_file "$driver")
                    if [ "$reused_module" -eq 1 ]; then
                        printf 'Driver SHA256: %s  %s\n' "$driver_sum" "${driver##*/}" \
                            >> "$out/BUILD-INFO.txt"
                    else
                        module_ready=1
                        release_driver=$driver
                    fi
                    printf 'OK    %-16s %-6s %-5s kernel=%s driver=%s  %s\n' \
                        "$label" "$cpu" "$mode" "$kernel_sum" "$driver_sum" "$out" >> "$SUMMARY"
                    echo "    OK -> $kernel + $driver"
                else
                    if [ -n "$copy_error" ]; then
                        reason=$copy_error
                    else
                        reason='missing or empty kernel/driver artifact'
                    fi
                    printf 'FAIL  %-16s %-6s %-5s (%s; see %s)\n' \
                        "$label" "$cpu" "$mode" "$reason" "$log" >> "$SUMMARY"
                    echo "    FAIL: $reason (see $log)" >&2
                    FAILED="$FAILED $label/$cpu-$mode"
                fi
            else
                printf 'FAIL  %-16s %-6s %-5s (build error; see %s)\n' \
                    "$label" "$cpu" "$mode" "$log" >> "$SUMMARY"
                echo "    FAIL: build error (see $log)" >&2
                FAILED="$FAILED $label/$cpu-$mode"
            fi
        done
    done
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo; echo "dry run complete; no builds executed"
    exit 0
fi

{
    echo
    echo "finished: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [ -n "$FAILED" ]; then echo "failed:$FAILED"; else echo "failed: none"; fi
} >> "$SUMMARY"

echo
echo "matrix summary: $SUMMARY"
cat "$SUMMARY"
if [ -n "$FAILED" ]; then
    echo "FAILED combinations:$FAILED" >&2
    exit 1
fi
echo "all matrix combinations built"
