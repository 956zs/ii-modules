#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_II_ROOT="$ROOT_DIR/spec/fixtures/ii-stock"
LINUX_BIN_NAME="iimod-linux-x86_64"
WORK_DIR=""

usage() {
    cat <<'EOF'
Usage: tools/release/verify.sh RELEASE_DIR

Verify release artifacts created by tools/release/build.sh.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$WORK_DIR" && "$WORK_DIR" == /tmp/ii-modules-verify.* ]]; then
        rm -rf "$WORK_DIR"
    fi
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

prepare_environment() {
    for cmd in find grep mktemp python3 sha256sum unzip; do
        need_command "$cmd"
    done
    [[ -d "$FIXTURE_II_ROOT" ]] || die "missing fixture II root: $FIXTURE_II_ROOT"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-modules-verify.XXXXXX")"
    trap cleanup EXIT
}

absolute_path() {
    python3 - "$1" <<'PY'
import pathlib
import sys

print(pathlib.Path(sys.argv[1]).resolve())
PY
}

run_with_fixture() {
    local state_root="$WORK_DIR/state-$1"
    shift
    IIMOD_II_ROOT="$FIXTURE_II_ROOT" \
        IIMOD_STATE_ROOT="$state_root" \
        IIMOD_SHELLCONFIG_ROOT="$WORK_DIR/shellconfig" \
        IIMOD_NO_QS=1 \
        "$@"
}

check_for_global_skill_install() {
    local root="$1"
    if grep -R -n -E 'cp -r .*~/.claude/skills|install.*~/.claude/skills|安裝.*~/.claude/skills|my-widget' \
        "$root/README.md" "$root/.claude" "$root/skills"; then
        die "starter contains stale global-skill install wording or hyphenated module id examples"
    fi
}

verify_top_level_checksums() {
    local release_dir="$1"
    [[ -f "$release_dir/SHA256SUMS" ]] || die "missing SHA256SUMS in $release_dir"
    (cd "$release_dir" && sha256sum -c SHA256SUMS)
}

verify_top_level_packages() {
    local release_dir="$1"
    local iimod_bin="$release_dir/$LINUX_BIN_NAME"
    [[ -x "$iimod_bin" ]] || die "missing executable release binary: $iimod_bin"
    compgen -G "$release_dir/*.iimod" >/dev/null || die "no .iimod packages in $release_dir"

    "$iimod_bin" --version
    for package in "$release_dir"/*.iimod; do
        "$iimod_bin" validate "$package"
        run_with_fixture "$(basename "$package")" "$iimod_bin" check "$package"
    done
}

verify_starter_zip() {
    local release_dir="$1"
    local starter_zip starter_root
    starter_zip="$(find "$release_dir" -maxdepth 1 -type f -name 'ii-modules-starter-*.zip' | sort | head -n 1)"
    [[ -n "$starter_zip" ]] || die "missing starter zip in $release_dir"

    unzip -q "$starter_zip" -d "$WORK_DIR/starter"
    starter_root="$(find "$WORK_DIR/starter" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
    [[ -n "$starter_root" ]] || die "starter zip has no root directory"
    [[ -f "$starter_root/.claude/skills/ii-module-author/SKILL.md" ]] || die "starter missing author project skill"
    [[ -f "$starter_root/.claude/skills/ii-module-manage/SKILL.md" ]] || die "starter missing manager project skill"

    (cd "$starter_root" && sha256sum -c SHA256SUMS)
    "$starter_root/bin/iimod" --version
    for package in "$starter_root"/modules/*.iimod; do
        "$starter_root/bin/iimod" validate "$package"
        run_with_fixture "starter-$(basename "$package")" "$starter_root/bin/iimod" check "$package"
    done
    check_for_global_skill_install "$starter_root"
}

main() {
    [[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
    [[ $# -eq 1 ]] || { usage >&2; exit 1; }
    prepare_environment

    local release_dir
    release_dir="$(absolute_path "$1")"
    [[ -d "$release_dir" ]] || die "release directory does not exist: $release_dir"

    verify_top_level_checksums "$release_dir"
    verify_top_level_packages "$release_dir"
    verify_starter_zip "$release_dir"
    printf 'release artifacts verified: %s\n' "$release_dir"
}

main "$@"
