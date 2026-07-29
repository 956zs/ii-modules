#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-publish-contracts.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

PASS_COUNT=0

expect_pass() {
    "$@" >"$WORK_DIR/command.out" 2>&1
    PASS_COUNT=$((PASS_COUNT + 1))
}

expect_fail() {
    if "$@" >"$WORK_DIR/unexpected.out" 2>&1; then
        printf 'expected command to fail: %q ' "$@" >&2
        printf '\n' >&2
        exit 1
    fi
    PASS_COUNT=$((PASS_COUNT + 1))
}

setup_repo() {
    local name="$1"
    local repo="$WORK_DIR/$name-repo"
    local remote="$WORK_DIR/$name-remote.git"
    mkdir -p "$repo/tools/release" "$repo/tools/iimod" "$repo/modules/example_module"
    cp "$SOURCE_ROOT/tools/release/common.sh" "$repo/tools/release/common.sh"
    cp "$SOURCE_ROOT/tools/release/publish.sh" "$repo/tools/release/publish.sh"
    chmod +x "$repo/tools/release/publish.sh"
    printf '{"id":"example_module","version":"1.2.3"}\n' > "$repo/modules/example_module/module.json"
    cat > "$repo/tools/iimod/Cargo.toml" <<'EOF'
[package]
name = "iimod"
version = "4.5.6"
edition = "2021"
EOF
    cat > "$repo/tools/release/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -z "${RELEASE_TEST_ASSERT_ABSENT:-}" || ! -e "$root/$RELEASE_TEST_ASSERT_ABSENT" ]]
if [[ -n "${RELEASE_TEST_BUILD_HOOK:-}" ]]; then
    "$RELEASE_TEST_BUILD_HOOK"
fi
release_tag="${*: -1}"
mkdir -p "$RELEASE_DIST_DIR/$release_tag"
printf '%s\n' "$release_tag" > "$RELEASE_DIST_DIR/$release_tag/built-tag"
EOF
    cat > "$repo/tools/release/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -f "$1/built-tag" ]]
[[ "$(<"$1/built-tag")" == "$2" ]]
EOF
    chmod +x "$repo/tools/release/build.sh" "$repo/tools/release/verify.sh"

    git -C "$repo" init -q -b main
    git -C "$repo" config user.name "Release Test"
    git -C "$repo" config user.email "release-test@example.invalid"
    git -C "$repo" add .
    git -C "$repo" commit -qm "test fixture"
    git init -q --bare "$remote"
    git -C "$repo" remote add origin "$remote"
    git -C "$repo" push -qu origin main
    printf '%s\n%s\n' "$repo" "$remote"
}

assert_no_release_tag() {
    local repo="$1" remote="$2"
    [[ -z "$(git -C "$repo" tag --list 'module/example_module/*')" ]]
    ! git --git-dir="$remote" rev-parse -q --verify refs/tags/module/example_module/v1.2.3 >/dev/null
}

test_basic_flow() {
    local paths repo remote
    paths="$(setup_repo basic)"
    repo="$(printf '%s\n' "$paths" | sed -n '1p')"
    remote="$(printf '%s\n' "$paths" | sed -n '2p')"

    expect_pass "$repo/tools/release/publish.sh" module example_module
    [[ -z "$(git -C "$repo" tag --list)" ]]
    grep -q 'release: module/example_module/v1.2.3' "$WORK_DIR/command.out"
    grep -q 'no tag created' "$WORK_DIR/command.out"

    printf 'dirty\n' > "$repo/untracked"
    expect_fail "$repo/tools/release/publish.sh" module example_module
    expect_pass "$repo/tools/release/publish.sh" module example_module --allow-dirty
    expect_fail "$repo/tools/release/publish.sh" module example_module --allow-dirty --push
    rm "$repo/untracked"

    expect_fail "$repo/tools/release/publish.sh" module
    expect_fail "$repo/tools/release/publish.sh" cli unexpected
    expect_fail "$repo/tools/release/publish.sh" module missing_module

    expect_pass "$repo/tools/release/publish.sh" module example_module --push
    git -C "$repo" rev-parse -q --verify refs/tags/module/example_module/v1.2.3 >/dev/null
    git --git-dir="$remote" rev-parse -q --verify refs/tags/module/example_module/v1.2.3 >/dev/null
    expect_fail "$repo/tools/release/publish.sh" module example_module --push

    git -C "$repo" switch -qc feature
    expect_fail "$repo/tools/release/publish.sh" cli --push
}

test_local_head_race() {
    local paths repo remote hook
    paths="$(setup_repo local-race)"
    repo="$(printf '%s\n' "$paths" | sed -n '1p')"
    remote="$(printf '%s\n' "$paths" | sed -n '2p')"
    hook="$WORK_DIR/local-head-hook.sh"
    cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'advanced\n' > '$repo/local-advance'
git -C '$repo' add local-advance
git -C '$repo' commit -qm 'advance local head during build'
EOF
    chmod +x "$hook"

    expect_fail env RELEASE_TEST_BUILD_HOOK="$hook" \
        "$repo/tools/release/publish.sh" module example_module --push
    assert_no_release_tag "$repo" "$remote"
}

test_remote_head_race() {
    local paths repo remote hook
    paths="$(setup_repo remote-race)"
    repo="$(printf '%s\n' "$paths" | sed -n '1p')"
    remote="$(printf '%s\n' "$paths" | sed -n '2p')"
    hook="$WORK_DIR/remote-head-hook.sh"
    cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
clone="\$(mktemp -d '${TMPDIR:-/tmp}/ii-publish-remote-race.XXXXXX')"
trap 'rm -rf "\$clone"' EXIT
git clone -q '$remote' "\$clone"
git -C "\$clone" config user.name 'Remote Race'
git -C "\$clone" config user.email 'remote-race@example.invalid'
printf 'advanced\n' > "\$clone/remote-advance"
git -C "\$clone" add remote-advance
git -C "\$clone" commit -qm 'advance remote head during build'
git -C "\$clone" push -q origin main
EOF
    chmod +x "$hook"

    expect_fail env RELEASE_TEST_BUILD_HOOK="$hook" \
        "$repo/tools/release/publish.sh" module example_module --push
    assert_no_release_tag "$repo" "$remote"
}

test_ignored_files_excluded() {
    local paths repo remote
    paths="$(setup_repo ignored)"
    repo="$(printf '%s\n' "$paths" | sed -n '1p')"
    remote="$(printf '%s\n' "$paths" | sed -n '2p')"
    printf '*.secret\n' > "$repo/.gitignore"
    git -C "$repo" add .gitignore
    git -C "$repo" commit -qm 'ignore local release debris'
    git -C "$repo" push -qu origin main
    printf 'must not ship\n' > "$repo/modules/example_module/private.secret"

    expect_pass env RELEASE_TEST_ASSERT_ABSENT='modules/example_module/private.secret' \
        "$repo/tools/release/publish.sh" module example_module --push
    git --git-dir="$remote" rev-parse -q --verify refs/tags/module/example_module/v1.2.3 >/dev/null
}

main() {
    test_basic_flow
    test_local_head_race
    test_remote_head_race
    test_ignored_files_excluded
    printf 'publish contract tests passed: %d\n' "$PASS_COUNT"
}

main "$@"
