#!/bin/sh
# Create canonical patches from vendored files at the configured upstream bases.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG=$ROOT/scripts/canonical-patch-config.sh
PATCH_ROOT=$ROOT/patches/canonical
[ -f "$CONFIG" ] || { echo "missing $CONFIG" >&2; exit 1; }
. "$CONFIG"

if [ "$#" -ne 0 ]; then
    echo "usage: $0" >&2
    exit 2
fi
command -v git >/dev/null 2>&1 || {
    echo "git is required" >&2
    exit 1
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/warpgfx-patches.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' 0 1 2 15

prepare_tree() (
    name=$1
    url=$2
    revision=$3
    paths=$4
    tree=$TMP_ROOT/$name

    git -C "$TMP_ROOT" init -q "$name"
    git -C "$tree" remote add origin "$url"
    git -C "$tree" config remote.origin.promisor true
    git -C "$tree" config remote.origin.partialclonefilter blob:none
    git -C "$tree" sparse-checkout init --no-cone
    set -- $paths
    git -C "$tree" sparse-checkout set --no-cone "$@"
    git -C "$tree" fetch -q --depth=1 --filter=blob:none origin "$revision"
    git -C "$tree" checkout -q --detach FETCH_HEAD

    actual=$(git -C "$tree" rev-parse HEAD)
    [ "$actual" = "$revision" ] || {
        echo "$name: expected $revision, fetched $actual" >&2
        exit 1
    }
)

generate_patch() (
    name=$1
    vendor=$2
    paths=$3
    output=$4
    tree=$TMP_ROOT/$name

    for path in $paths; do
        source_file=$ROOT/$vendor/$path
        [ -f "$source_file" ] || {
            echo "missing vendored source: $vendor/$path" >&2
            exit 1
        }
        mkdir -p "$tree/$(dirname -- "$path")"
        cp "$source_file" "$tree/$path"
    done

    set -- $paths
    git -C "$tree" add -N -- "$@"
    git -C "$tree" diff --check -- "$@"
    git -C "$tree" diff --no-ext-diff --full-index --binary -- "$@" > "$output"
    [ -s "$output" ] || {
        echo "$name: generated patch is empty" >&2
        exit 1
    }
    git -C "$tree" apply --check --reverse --whitespace=nowarn "$output"
    git -C "$tree" apply --reverse --whitespace=nowarn "$output"
    git -C "$tree" reset -q -- "$@"
    git -C "$tree" apply --check --whitespace=nowarn "$output"
    git -C "$tree" diff --exit-code -- "$@"
)

sha256_file() {
    if command -v sha256 >/dev/null 2>&1; then
        sha256 -q "$1"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | sed 's/[[:space:]].*//'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | sed 's/[[:space:]].*//'
    else
        echo "sha256, shasum, or sha256sum is required" >&2
        return 1
    fi
}

write_checksums() {
    output=$1
    for file in netbsd-src-warpgfx.patch netbsd-xsrc-warpgfx-wsfb-exa.patch; do
        printf '%s  %s\n' "$(sha256_file "$TMP_ROOT/$file")" "$file"
    done > "$output"
}

prepare_tree src "$SRC_URL" "$SRC_BASE" "$SRC_PATHS"
prepare_tree xsrc "$XSRC_URL" "$XSRC_BASE" "$XSRC_PATHS"
generate_patch src src "$SRC_PATHS" "$TMP_ROOT/netbsd-src-warpgfx.patch"
generate_patch xsrc xsrc "$XSRC_PATHS" "$TMP_ROOT/netbsd-xsrc-warpgfx-wsfb-exa.patch"
write_checksums "$TMP_ROOT/SHA256.txt"

mkdir -p "$PATCH_ROOT"
mv "$TMP_ROOT/netbsd-src-warpgfx.patch" "$PATCH_ROOT/netbsd-src-warpgfx.patch"
mv "$TMP_ROOT/netbsd-xsrc-warpgfx-wsfb-exa.patch" "$PATCH_ROOT/netbsd-xsrc-warpgfx-wsfb-exa.patch"
mv "$TMP_ROOT/SHA256.txt" "$PATCH_ROOT/SHA256.txt"

echo "Generated and verified:"
echo "  $PATCH_ROOT/netbsd-src-warpgfx.patch"
echo "  $PATCH_ROOT/netbsd-xsrc-warpgfx-wsfb-exa.patch"
echo "  $PATCH_ROOT/SHA256.txt"
