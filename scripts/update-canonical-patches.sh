#!/bin/sh
# Three-way rebase the WarpGFX patches onto newer NetBSD src/xsrc commits.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIG=$ROOT/scripts/canonical-patch-config.sh
CANONICAL_REL=patches/canonical
CANONICAL=$ROOT/$CANONICAL_REL
[ -f "$CONFIG" ] || { echo "missing $CONFIG" >&2; exit 1; }
. "$CONFIG"

usage() {
    cat >&2 <<EOF
usage: $0 --latest [--dry-run] [--keep-temp] [--allow-non-fast-forward]
       $0 --src REV --xsrc REV [--dry-run] [--keep-temp]

--latest resolves each official mirror's current HEAD once and pins its commit.
Explicit revisions may be commit IDs, tags, or branch names.
EOF
}

LATEST=0
DRY_RUN=0
KEEP_TEMP=0
ALLOW_NON_FF=0
SRC_TARGET=
XSRC_TARGET=
while [ "$#" -gt 0 ]; do
    case $1 in
        --latest) LATEST=1; shift ;;
        --src) [ "$#" -ge 2 ] || { usage; exit 2; }; SRC_TARGET=$2; shift 2 ;;
        --xsrc) [ "$#" -ge 2 ] || { usage; exit 2; }; XSRC_TARGET=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --keep-temp) KEEP_TEMP=1; shift ;;
        --allow-non-fast-forward) ALLOW_NON_FF=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
done

if [ "$LATEST" -eq 1 ]; then
    [ -z "$SRC_TARGET$XSRC_TARGET" ] || { usage; exit 2; }
    SRC_TARGET=HEAD
    XSRC_TARGET=HEAD
else
    [ -n "$SRC_TARGET" ] && [ -n "$XSRC_TARGET" ] || { usage; exit 2; }
fi
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/warpgfx-update.XXXXXX")
CANDIDATE=$TMP_ROOT/candidate
BACKUP=$TMP_ROOT/backup
PRESERVE=$KEEP_TEMP
INSTALLING=0
mkdir -p "$CANDIDATE/$CANONICAL_REL" "$BACKUP"

restore_backup() {
    [ -f "$BACKUP/files" ] || return 0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        cp "$BACKUP/$path" "$ROOT/$path"
    done < "$BACKUP/files"
}

cleanup() {
    status=$?
    trap - 0 1 2 15
    if [ "$INSTALLING" -eq 1 ]; then
        echo "installation failed; restoring original files" >&2
        set +e
        restore_backup
        set -e
    fi
    if [ "$PRESERVE" -eq 1 ]; then
        echo "temporary work retained at: $TMP_ROOT" >&2
    else
        rm -rf "$TMP_ROOT"
    fi
    exit "$status"
}
trap cleanup 0 1 2 15

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dirty=$(git -C "$ROOT" status --porcelain -- \
        scripts/canonical-patch-config.sh src xsrc patches/canonical)
    [ -z "$dirty" ] || {
        echo "managed files have uncommitted changes; commit or revert them first:" >&2
        echo "$dirty" >&2
        exit 1
    }
fi

path_allowed() {
    candidate_path=$1
    allowed_paths=$2
    for allowed_path in $allowed_paths; do
        [ "$candidate_path" = "$allowed_path" ] && return 0
    done
    return 1
}

validate_delta() {
    delta_repo=$1
    delta_base=$2
    delta_head=$3
    delta_paths=$4
    changed_file=$TMP_ROOT/changed.$$

    git -C "$delta_repo" diff --name-only "$delta_base" "$delta_head" > "$changed_file"
    [ -s "$changed_file" ] || {
        echo "rebased patch is empty (the change may already be upstream)" >&2
        return 1
    }
    while IFS= read -r changed_path; do
        [ -n "$changed_path" ] || continue
        path_allowed "$changed_path" "$delta_paths" || {
            echo "rebased patch unexpectedly changes: $changed_path" >&2
            return 1
        }
    done < "$changed_file"

    bad_paths=$(git -C "$delta_repo" diff --name-only --diff-filter=DRTUXB \
        "$delta_base" "$delta_head")
    [ -z "$bad_paths" ] || {
        echo "deletions, renames, or type changes are not supported:" >&2
        echo "$bad_paths" >&2
        return 1
    }
    for managed_path in $delta_paths; do
        entry=$(git -C "$delta_repo" ls-tree "$delta_head" -- "$managed_path")
        metadata=${entry%%	*}
        mode=${metadata%% *}
        [ "$mode" = 100644 ] || {
            echo "managed path is missing or not a regular 0644 file: $managed_path" >&2
            return 1
        }
    done
}

verify_vendor_matches() {
    verify_repo=$1
    verify_vendor=$2
    verify_paths=$3
    for verify_path in $verify_paths; do
        cmp "$ROOT/$verify_vendor/$verify_path" "$verify_repo/$verify_path" >/dev/null || {
            echo "$verify_vendor/$verify_path does not match the checked-in patch" >&2
            echo "regenerate the patch before updating its base" >&2
            return 1
        }
    done
}

prepare_rebased_tree() {
    update_name=$1
    update_url=$2
    update_old=$3
    update_target=$4
    update_paths=$5
    update_patch=$6
    update_vendor=$7
    update_repo=$TMP_ROOT/$update_name

    echo "$update_name: fetching old base and target $update_target ..."
    git -C "$TMP_ROOT" init -q "$update_name"
    git -C "$update_repo" remote add origin "$update_url"
    git -C "$update_repo" config remote.origin.promisor true
    git -C "$update_repo" config remote.origin.partialclonefilter blob:none
    git -C "$update_repo" config user.name 'WarpGFX patch updater'
    git -C "$update_repo" config user.email 'warpgfx-patch-updater@invalid'
    git -C "$update_repo" sparse-checkout init --no-cone
    set -- $update_paths
    git -C "$update_repo" sparse-checkout set --no-cone "$@"

    git -C "$update_repo" fetch -q --filter=blob:none origin "$update_old"
    fetched_old=$(git -C "$update_repo" rev-parse 'FETCH_HEAD^{commit}')
    [ "$fetched_old" = "$update_old" ] || {
        echo "$update_name: configured base resolved unexpectedly: $fetched_old" >&2
        return 1
    }

    git -C "$update_repo" fetch -q --filter=blob:none origin "$update_target"
    update_new=$(git -C "$update_repo" rev-parse 'FETCH_HEAD^{commit}')
    git -C "$update_repo" cat-file -e "$update_new^{commit}"
    [ "$update_new" != "$update_old" ] || {
        echo "$update_name: target is already the configured base" >&2
        return 1
    }
    if [ "$ALLOW_NON_FF" -eq 0 ] && \
        ! git -C "$update_repo" merge-base --is-ancestor "$update_old" "$update_new"; then
        echo "$update_name: target is not a descendant of the configured base" >&2
        echo "use --allow-non-fast-forward only after reviewing the history change" >&2
        return 1
    fi

    git -C "$update_repo" checkout -q --detach "$update_old"
    git -C "$update_repo" apply --check --whitespace=nowarn "$CANONICAL/$update_patch"
    git -C "$update_repo" apply --index --whitespace=nowarn "$CANONICAL/$update_patch"
    git -C "$update_repo" diff --cached --check
    verify_vendor_matches "$update_repo" "$update_vendor" "$update_paths"
    git -C "$update_repo" commit -qm 'WarpGFX local patch'
    local_commit=$(git -C "$update_repo" rev-parse HEAD)
    validate_delta "$update_repo" "$update_old" "$local_commit" "$update_paths"

    git -C "$update_repo" checkout -q --detach "$update_new"
    if ! git -C "$update_repo" cherry-pick "$local_commit"; then
        PRESERVE=1
        echo "$update_name: three-way rebase conflicted" >&2
        git -C "$update_repo" status --short >&2
        echo "resolve and review in $update_repo, then rerun with explicit revisions" >&2
        return 1
    fi
    rebased_commit=$(git -C "$update_repo" rev-parse HEAD)
    validate_delta "$update_repo" "$update_new" "$rebased_commit" "$update_paths"
    git -C "$update_repo" diff --check "$update_new" "$rebased_commit"

    set -- $update_paths
    git -C "$update_repo" diff --no-ext-diff --full-index --binary \
        "$update_new" "$rebased_commit" -- "$@" > "$CANDIDATE/$CANONICAL_REL/$update_patch"
    [ -s "$CANDIDATE/$CANONICAL_REL/$update_patch" ] || {
        echo "$update_name: generated patch is empty" >&2
        return 1
    }
    expected_tree=$(git -C "$update_repo" rev-parse "$rebased_commit^{tree}")
    git -C "$update_repo" apply --check --reverse --whitespace=nowarn \
        "$CANDIDATE/$CANONICAL_REL/$update_patch"
    git -C "$update_repo" checkout -q --detach "$update_new"
    git -C "$update_repo" apply --check --whitespace=nowarn "$CANDIDATE/$CANONICAL_REL/$update_patch"
    git -C "$update_repo" apply --index --whitespace=nowarn "$CANDIDATE/$CANONICAL_REL/$update_patch"
    actual_tree=$(git -C "$update_repo" write-tree)
    [ "$actual_tree" = "$expected_tree" ] || {
        echo "$update_name: patch verification produced a different tree" >&2
        return 1
    }

    for update_path in $update_paths; do
        destination=$CANDIDATE/$update_vendor/$update_path
        mkdir -p "$(dirname -- "$destination")"
        cp "$update_repo/$update_path" "$destination"
    done
    printf '%s\n' "$update_new" > "$TMP_ROOT/$update_name.new"
    echo "$update_name: rebased $update_old -> $update_new"
}

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
    checksum_output=$1
    for checksum_name in netbsd-src-warpgfx.patch netbsd-xsrc-warpgfx-wsfb-exa.patch; do
        checksum_input=$CANDIDATE/$CANONICAL_REL/$checksum_name
        printf '%s  %s\n' "$(sha256_file "$checksum_input")" "$checksum_name"
    done > "$checksum_output"
}

prepare_rebased_tree src "$SRC_URL" "$SRC_BASE" "$SRC_TARGET" "$SRC_PATHS" \
    netbsd-src-warpgfx.patch src
prepare_rebased_tree xsrc "$XSRC_URL" "$XSRC_BASE" "$XSRC_TARGET" "$XSRC_PATHS" \
    netbsd-xsrc-warpgfx-wsfb-exa.patch xsrc
NEW_SRC_BASE=$(cat "$TMP_ROOT/src.new")
NEW_XSRC_BASE=$(cat "$TMP_ROOT/xsrc.new")

sed -e "s/^SRC_BASE=.*/SRC_BASE='$NEW_SRC_BASE'/" \
    -e "s/^XSRC_BASE=.*/XSRC_BASE='$NEW_XSRC_BASE'/" \
    "$CONFIG" > "$CANDIDATE/scripts.canonical-patch-config.sh"
mkdir -p "$CANDIDATE/scripts"
mv "$CANDIDATE/scripts.canonical-patch-config.sh" \
    "$CANDIDATE/scripts/canonical-patch-config.sh"
write_checksums "$CANDIDATE/$CANONICAL_REL/SHA256.txt"

INSTALL_PATHS="scripts/canonical-patch-config.sh
$CANONICAL_REL/netbsd-src-warpgfx.patch
$CANONICAL_REL/netbsd-xsrc-warpgfx-wsfb-exa.patch
$CANONICAL_REL/SHA256.txt"
for install_path in $SRC_PATHS; do
    INSTALL_PATHS="$INSTALL_PATHS
src/$install_path"
done
for install_path in $XSRC_PATHS; do
    INSTALL_PATHS="$INSTALL_PATHS
xsrc/$install_path"
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run successful; no repository files were changed"
    echo "new src base:  $NEW_SRC_BASE"
    echo "new xsrc base: $NEW_XSRC_BASE"
    exit 0
fi

: > "$BACKUP/files"
for install_path in $INSTALL_PATHS; do
    backup_path=$BACKUP/$install_path
    mkdir -p "$(dirname -- "$backup_path")"
    cp "$ROOT/$install_path" "$backup_path"
    printf '%s\n' "$install_path" >> "$BACKUP/files"
done

INSTALLING=1
for install_path in $INSTALL_PATHS; do
    cp "$CANDIDATE/$install_path" "$ROOT/$install_path"
done
INSTALLING=0

echo "updated WarpGFX patches and vendored sources"
echo "new src base:  $NEW_SRC_BASE"
echo "new xsrc base: $NEW_XSRC_BASE"
echo "textual checks passed; build the amiga kernel and wsfb module before release"
