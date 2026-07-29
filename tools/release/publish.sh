#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLS_DIR/common.sh"

PUSH=0
ALLOW_DIRTY=0
PRODUCT=""
MODULE_ID=""
REMOTE="${RELEASE_REMOTE:-origin}"
RELEASE_TAG=""
RELEASE_DIR=""
WORK_DIR=""
BUILD_ROOT=""
EXPECTED_HEAD=""

usage() {
    cat <<'EOF'
Usage:
  tools/release/publish.sh module <id> [--push]
  tools/release/publish.sh cli [--push]

Build and verify one release using the version declared by the product.
Without --push, this is a local dry-run and does not create a tag.
With --push, the command requires a clean, synchronized main branch, creates
an annotated tag, and pushes only that tag to trigger GitHub Actions.

Options:
  --push          Create and push the release tag after verification.
  --allow-dirty   Allow a dirty tree for a local dry-run only.
  -h, --help      Show this help.
EOF
}

cleanup() {
    if [[ -n "$BUILD_ROOT" && -n "$EXPECTED_HEAD" ]]; then
        git -C "$ROOT_DIR" worktree remove --force "$BUILD_ROOT" >/dev/null 2>&1 || true
    fi
    if [[ -n "$WORK_DIR" && "$WORK_DIR" == "${TMPDIR:-/tmp}"/ii-publish.* ]]; then
        rm -rf "$WORK_DIR"
    fi
}

parse_args() {
    while (($#)); do
        case "$1" in
            --push) PUSH=1 ;;
            --allow-dirty) ALLOW_DIRTY=1 ;;
            -h|--help) usage; exit 0 ;;
            module|cli)
                [[ -z "$PRODUCT" ]] || die "product provided more than once"
                PRODUCT="$1"
                ;;
            -*) die "unknown option: $1" ;;
            *)
                [[ "$PRODUCT" == module && -z "$MODULE_ID" ]] \
                    || die "unexpected argument: $1"
                MODULE_ID="$1"
                ;;
        esac
        shift
    done

    [[ -n "$PRODUCT" ]] || { usage >&2; exit 1; }
    if [[ "$PRODUCT" == module ]]; then
        [[ -n "$MODULE_ID" ]] || die "module id is required"
    elif [[ -n "$MODULE_ID" ]]; then
        die "CLI releases do not accept a module id"
    fi
    ((PUSH == 0 || ALLOW_DIRTY == 0)) \
        || die "--allow-dirty cannot be combined with --push"
}

derive_release() {
    if [[ "$PRODUCT" == module ]]; then
        local module_dir="$ROOT_DIR/modules/$MODULE_ID"
        local manifest_id manifest_version
        [[ -d "$module_dir" ]] || die "module not found: modules/$MODULE_ID"
        manifest_id="$(module_json_field "$module_dir/module.json" id)"
        manifest_version="$(module_json_field "$module_dir/module.json" version)"
        [[ "$manifest_id" == "$MODULE_ID" ]] \
            || die "requested module '$MODULE_ID' has manifest id '$manifest_id'"
        RELEASE_TAG="module/$MODULE_ID/v$manifest_version"
        validate_module_contract "$module_dir" "$RELEASE_TAG"
    else
        local cargo_version
        cargo_version="$(cargo_package_version)"
        RELEASE_TAG="iimod/v$cargo_version"
        validate_cli_contract "$RELEASE_TAG" "$cargo_version"
    fi
}

require_push_ready() {
    local branch
    branch="$(git -C "$ROOT_DIR" branch --show-current)"
    [[ "$branch" == main ]] || die "--push requires branch main, current branch: ${branch:-detached HEAD}"
    require_clean_tree 0

    git -C "$ROOT_DIR" fetch --quiet "$REMOTE" main --tags
    EXPECTED_HEAD="$(git -C "$ROOT_DIR" rev-parse HEAD)"
    [[ "$EXPECTED_HEAD" == "$(git -C "$ROOT_DIR" rev-parse "$REMOTE/main")" ]] \
        || die "HEAD must exactly match $REMOTE/main before publishing"
    ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null \
        || die "local tag already exists: $RELEASE_TAG"
    [[ -z "$(git -C "$ROOT_DIR" ls-remote --tags "$REMOTE" "refs/tags/$RELEASE_TAG")" ]] \
        || die "remote tag already exists: $RELEASE_TAG"
}

create_release_worktree() {
    [[ -n "$EXPECTED_HEAD" ]] || die "internal error: missing expected release commit"
    BUILD_ROOT="$WORK_DIR/source"
    git -C "$ROOT_DIR" worktree add --quiet --detach "$BUILD_ROOT" "$EXPECTED_HEAD"
}

build_and_verify() {
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-publish.XXXXXX")"
    trap cleanup EXIT
    RELEASE_DIR="$WORK_DIR/$RELEASE_TAG"

    local dirty_args=()
    ((ALLOW_DIRTY == 0)) || dirty_args+=(--allow-dirty)
    if ((PUSH == 1)); then
        create_release_worktree
        RELEASE_DIST_DIR="$WORK_DIR" "$BUILD_ROOT/tools/release/build.sh" "$RELEASE_TAG"
        "$BUILD_ROOT/tools/release/verify.sh" "$RELEASE_DIR" "$RELEASE_TAG"
    else
        RELEASE_DIST_DIR="$WORK_DIR" "$TOOLS_DIR/build.sh" "${dirty_args[@]}" "$RELEASE_TAG"
        "$TOOLS_DIR/verify.sh" "$RELEASE_DIR" "$RELEASE_TAG"
    fi
}

recheck_push_ready() {
    local branch head remote_head
    branch="$(git -C "$ROOT_DIR" branch --show-current)"
    [[ "$branch" == main ]] || die "branch changed during verification"
    require_clean_tree 0
    head="$(git -C "$ROOT_DIR" rev-parse HEAD)"
    [[ "$head" == "$EXPECTED_HEAD" ]] || die "HEAD changed during verification"

    git -C "$ROOT_DIR" fetch --quiet "$REMOTE" main --tags
    remote_head="$(git -C "$ROOT_DIR" rev-parse "$REMOTE/main")"
    [[ "$remote_head" == "$EXPECTED_HEAD" ]] || die "$REMOTE/main changed during verification"
    ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null \
        || die "local tag appeared during verification: $RELEASE_TAG"
    [[ -z "$(git -C "$ROOT_DIR" ls-remote --tags "$REMOTE" "refs/tags/$RELEASE_TAG")" ]] \
        || die "remote tag appeared during verification: $RELEASE_TAG"
}

push_tag() {
    local message="Release $RELEASE_TAG"
    recheck_push_ready
    git -C "$ROOT_DIR" tag -a "$RELEASE_TAG" "$EXPECTED_HEAD" -m "$message"
    if ! git -C "$ROOT_DIR" push --atomic \
        --force-with-lease="refs/heads/main:$EXPECTED_HEAD" \
        "$REMOTE" \
        "refs/heads/main:refs/heads/main" \
        "refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"; then
        git -C "$ROOT_DIR" tag -d "$RELEASE_TAG" >/dev/null
        die "atomic tag push failed; removed local tag $RELEASE_TAG"
    fi
}

main() {
    parse_args "$@"
    for cmd in cargo git mktemp python3 realpath sha256sum; do need_command "$cmd"; done
    derive_release

    if ((PUSH == 1)); then
        require_push_ready
    else
        require_clean_tree "$ALLOW_DIRTY"
    fi

    printf 'release: %s\n' "$RELEASE_TAG"
    printf 'mode: %s\n' "$([[ $PUSH == 1 ]] && printf publish || printf dry-run)"
    build_and_verify

    if ((PUSH == 0)); then
        printf '✓ verified %s; no tag created\n' "$RELEASE_TAG"
        printf 'publish with: tools/release/publish.sh %s%s --push\n' \
            "$PRODUCT" "$([[ $PRODUCT == module ]] && printf ' %s' "$MODULE_ID")"
        return
    fi

    push_tag
    printf '✓ pushed %s; GitHub Actions will create the Release\n' "$RELEASE_TAG"
}

main "$@"
