#!/bin/sh
# Generate per-release WarpGFX patches by three-way rebasing the canonical
# patches (at the pinned base in canonical-patch-config.sh) onto each release commit
# listed in create-release-patches.conf.
#
# This is non-destructive: it never rewrites patches/canonical/, the vendored
# overlays, or canonical-patch-config.sh. It writes per-release artifacts under
# patches/<label>/ only. A cherry-pick conflict for a release
# is reported and that release is skipped; other releases still run. The script
# exits non-zero if any requested release failed.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG=$ROOT/scripts/canonical-patch-config.sh
MANIFEST=$ROOT/scripts/create-release-patches.conf
CANONICAL=$ROOT/patches/canonical
SRC_PATCH=netbsd-src-warpgfx.patch
XSRC_PATCH=netbsd-xsrc-warpgfx-wsfb-exa.patch

[ -f "$CONFIG" ] || { echo "missing $CONFIG" >&2; exit 1; }
[ -f "$MANIFEST" ] || { echo "missing $MANIFEST" >&2; exit 1; }
# shellcheck source=canonical-patch-config.sh
# shellcheck disable=SC1091
. "$CONFIG"
[ -r "$CANONICAL/$SRC_PATCH" ] || { echo "missing $CANONICAL/$SRC_PATCH" >&2; exit 1; }
[ -r "$CANONICAL/$XSRC_PATCH" ] || { echo "missing $CANONICAL/$XSRC_PATCH" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }

usage() {
    cat >&2 <<EOF
usage: $0 [--only LABEL] [--keep-temp]

Generates per-release patches for every record in
scripts/create-release-patches.conf and writes them under patches/<label>/.
--only restricts generation to one label.
EOF
}

ONLY_LABEL=
KEEP_TEMP=0
while [ "$#" -gt 0 ]; do
    case $1 in
        --only) [ "$#" -ge 2 ] || { usage; exit 2; }; ONLY_LABEL=$2; shift 2 ;;
        --keep-temp) KEEP_TEMP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/warpgfx-relpatch.XXXXXX")
cleanup() {
    status=$?
    trap - 0 1 2 15
    if [ "$KEEP_TEMP" -eq 1 ]; then
        echo "temporary work retained at: $TMP_ROOT" >&2
    else
        rm -rf "$TMP_ROOT"
    fi
    exit "$status"
}
trap cleanup 0 1 2 15

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

path_allowed() {
    for allowed_path in $2; do
        [ "$1" = "$allowed_path" ] && return 0
    done
    return 1
}

# Confirm a rebased delta only touches managed regular files.
validate_delta() {
    delta_repo=$1
    delta_base=$2
    delta_head=$3
    delta_paths=$4
    changed_file=$TMP_ROOT/changed.$$

    git -C "$delta_repo" diff --name-only "$delta_base" "$delta_head" > "$changed_file"
    [ -s "$changed_file" ] || { echo "  rebased patch is empty" >&2; rm -f "$changed_file"; return 1; }
    while IFS= read -r changed_path; do
        [ -n "$changed_path" ] || continue
        path_allowed "$changed_path" "$delta_paths" || {
            echo "  rebased patch unexpectedly changes: $changed_path" >&2
            rm -f "$changed_file"; return 1; }
    done < "$changed_file"
    rm -f "$changed_file"

    bad_paths=$(git -C "$delta_repo" diff --name-only --diff-filter=DRTUXB \
        "$delta_base" "$delta_head")
    [ -z "$bad_paths" ] || {
        echo "  deletions, renames, or type changes are not supported:" >&2
        echo "$bad_paths" >&2; return 1; }
    for managed_path in $delta_paths; do
        entry=$(git -C "$delta_repo" ls-tree "$delta_head" -- "$managed_path")
        metadata=${entry%%	*}
        mode=${metadata%% *}
        [ "$mode" = 100644 ] || {
            echo "  managed path missing or not a regular 0644 file: $managed_path" >&2
            return 1; }
    done
}

# Rebase one tree's canonical patch onto one release commit; emit release patch.
# Returns 0 on success, 1 on failure (conflict or verification error).
rebase_tree() {
    rt_name=$1        # src | xsrc
    rt_url=$2
    rt_old=$3         # canonical base commit
    rt_target=$4      # release commit
    rt_paths=$5
    rt_patch=$6       # canonical patch file (basename under $ROOT)
    rt_out=$7         # output patch file path
    rt_repo=$TMP_ROOT/${rt_label}.${rt_name}

    echo "  [$rt_name] fetching base and target..."
    git -C "$TMP_ROOT" init -q "${rt_label}.${rt_name}"
    git -C "$rt_repo" remote add origin "$rt_url"
    git -C "$rt_repo" config remote.origin.promisor true
    git -C "$rt_repo" config remote.origin.partialclonefilter blob:none
    git -C "$rt_repo" config user.name 'WarpGFX release patcher'
    git -C "$rt_repo" config user.email 'warpgfx-release-patcher@invalid'
    git -C "$rt_repo" sparse-checkout init --no-cone
    # shellcheck disable=SC2086
    set -- $rt_paths
    git -C "$rt_repo" sparse-checkout set --no-cone "$@"

    git -C "$rt_repo" fetch -q --filter=blob:none origin "$rt_old"
    fetched_old=$(git -C "$rt_repo" rev-parse 'FETCH_HEAD^{commit}')
    [ "$fetched_old" = "$rt_old" ] || {
        echo "  [$rt_name] base resolved unexpectedly: $fetched_old" >&2; return 1; }

    git -C "$rt_repo" fetch -q --filter=blob:none origin "$rt_target"
    rt_new=$(git -C "$rt_repo" rev-parse 'FETCH_HEAD^{commit}')
    [ "$rt_new" = "$rt_target" ] || {
        echo "  [$rt_name] target resolved unexpectedly: $rt_new (wanted $rt_target)" >&2; return 1; }

    # Build the canonical WarpGFX delta as a commit on top of the base.
    git -C "$rt_repo" checkout -q --detach "$rt_old"
    git -C "$rt_repo" apply --check --whitespace=nowarn "$CANONICAL/$rt_patch"
    git -C "$rt_repo" apply --index --whitespace=nowarn "$CANONICAL/$rt_patch"
    git -C "$rt_repo" diff --cached --check
    git -C "$rt_repo" commit -qm 'WarpGFX canonical patch'
    rt_local=$(git -C "$rt_repo" rev-parse HEAD)

    # Three-way apply that delta onto the release commit.
    git -C "$rt_repo" checkout -q --detach "$rt_new"
    if ! git -C "$rt_repo" cherry-pick "$rt_local" >/dev/null 2>&1; then
        echo "  [$rt_name] CONFLICT rebasing onto $rt_new:" >&2
        git -C "$rt_repo" status --short >&2 || true
        git -C "$rt_repo" cherry-pick --abort >/dev/null 2>&1 || true
        KEEP_TEMP=1
        return 1
    fi
    rt_rebased=$(git -C "$rt_repo" rev-parse HEAD)
    validate_delta "$rt_repo" "$rt_new" "$rt_rebased" "$rt_paths" || return 1
    git -C "$rt_repo" diff --check "$rt_new" "$rt_rebased"

    # shellcheck disable=SC2086
    set -- $rt_paths
    git -C "$rt_repo" diff --no-ext-diff --full-index --binary \
        "$rt_new" "$rt_rebased" -- "$@" > "$rt_out"
    [ -s "$rt_out" ] || { echo "  [$rt_name] generated patch is empty" >&2; return 1; }

    # Forward + reverse verification and exact tree comparison.
    expected_tree=$(git -C "$rt_repo" rev-parse "$rt_rebased^{tree}")
    git -C "$rt_repo" apply --check --reverse --whitespace=nowarn "$rt_out"
    git -C "$rt_repo" checkout -q --detach "$rt_new"
    git -C "$rt_repo" apply --check --whitespace=nowarn "$rt_out"
    git -C "$rt_repo" apply --index --whitespace=nowarn "$rt_out"
    actual_tree=$(git -C "$rt_repo" write-tree)
    [ "$actual_tree" = "$expected_tree" ] || {
        echo "  [$rt_name] patch verification produced a different tree" >&2; return 1; }
    return 0
}

FAILED=
GENERATED=
while IFS= read -r line || [ -n "$line" ]; do
    case $line in
        ''|\#*) continue ;;
    esac
    rt_label=${line%%|*}
    rest=${line#*|}
    src_commit=${rest%%|*}
    xsrc_commit=${rest#*|}
    case $rt_label in
        *[!A-Za-z0-9._-]*) echo "invalid label (unsafe characters): $rt_label" >&2; FAILED="$FAILED $rt_label"; continue ;;
    esac
    case $src_commit in ''|*[!0-9a-f]*) echo "$rt_label: bad src commit" >&2; FAILED="$FAILED $rt_label"; continue ;; esac
    case $xsrc_commit in ''|*[!0-9a-f]*) echo "$rt_label: bad xsrc commit" >&2; FAILED="$FAILED $rt_label"; continue ;; esac
    [ "${#src_commit}" -eq 40 ] || { echo "$rt_label: src commit not 40 chars" >&2; FAILED="$FAILED $rt_label"; continue; }
    [ "${#xsrc_commit}" -eq 40 ] || { echo "$rt_label: xsrc commit not 40 chars" >&2; FAILED="$FAILED $rt_label"; continue; }
    if [ -n "$ONLY_LABEL" ] && [ "$rt_label" != "$ONLY_LABEL" ]; then
        continue
    fi

    echo "==> $rt_label (src $src_commit / xsrc $xsrc_commit)"
    out_dir=$TMP_ROOT/out.$rt_label
    mkdir -p "$out_dir"
    ok=1
    rebase_tree src "$SRC_URL" "$SRC_BASE" "$src_commit" "$SRC_PATHS" \
        "$SRC_PATCH" "$out_dir/$SRC_PATCH" || ok=0
    if [ "$ok" -eq 1 ]; then
        rebase_tree xsrc "$XSRC_URL" "$XSRC_BASE" "$xsrc_commit" "$XSRC_PATHS" \
            "$XSRC_PATCH" "$out_dir/$XSRC_PATCH" || ok=0
    fi
    if [ "$ok" -eq 0 ]; then
        echo "  FAILED: $rt_label (left canonical repo untouched)" >&2
        FAILED="$FAILED $rt_label"
        continue
    fi

    # Publish this release's artifacts atomically.
    rel_dir=$ROOT/patches/$rt_label
    mkdir -p "$rel_dir"
    cp "$out_dir/$SRC_PATCH" "$rel_dir/$SRC_PATCH"
    cp "$out_dir/$XSRC_PATCH" "$rel_dir/$XSRC_PATCH"

    # Per-release canonical-patch-config.sh: canonical config with bases repinned.
    sed -e "s/^SRC_BASE=.*/SRC_BASE='$src_commit'/" \
        -e "s/^XSRC_BASE=.*/XSRC_BASE='$xsrc_commit'/" \
        "$CONFIG" > "$rel_dir/canonical-patch-config.sh"

    # Per-release checksums, keyed by basename (build script reads basenames).
    {
        printf '%s  %s\n' "$(sha256_file "$rel_dir/$SRC_PATCH")" "$SRC_PATCH"
        printf '%s  %s\n' "$(sha256_file "$rel_dir/$XSRC_PATCH")" "$XSRC_PATCH"
    } > "$rel_dir/SHA256.txt"

    {
        echo "WarpGFX release patch set"
        echo "label:       $rt_label"
        echo "src commit:  $src_commit"
        echo "xsrc commit: $xsrc_commit"
        echo "src url:     $SRC_URL"
        echo "xsrc url:    $XSRC_URL"
        echo "rebased from canonical base:"
        echo "  SRC_BASE:  $SRC_BASE"
        echo "  XSRC_BASE: $XSRC_BASE"
    } > "$rel_dir/RELEASE-INFO.txt"

    echo "  wrote $rel_dir/"
    GENERATED="$GENERATED $rt_label"
done < "$MANIFEST"

echo
echo "generated:${GENERATED:- (none)}"
if [ -n "$FAILED" ]; then
    echo "FAILED:${FAILED}" >&2
    exit 1
fi
echo "all requested releases generated and verified"
