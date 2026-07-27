#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-release-contracts.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

PASS_COUNT=0

expect_pass() {
    "$@" >/dev/null
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

write_manifest() {
    local directory="$1" id="$2" version="$3"
    mkdir -p "$directory"
    printf '{"id":"%s","version":"%s"}\n' "$id" "$version" > "$directory/module.json"
}

main() {
    local valid_module="$WORK_DIR/modules/example_module"
    local prerelease_module="$WORK_DIR/modules/prerelease_module"
    local wrong_dir="$WORK_DIR/modules/wrong_directory"
    write_manifest "$valid_module" example_module 1.2.3
    write_manifest "$prerelease_module" prerelease_module 1.2.3-rc.1
    write_manifest "$wrong_dir" example_module 1.2.3

    expect_pass "$TOOLS_DIR/contract.sh" module "$valid_module" module/example_module/v1.2.3
    expect_pass "$TOOLS_DIR/contract.sh" module "$prerelease_module" module/prerelease_module/v1.2.3-rc.1
    expect_fail "$TOOLS_DIR/contract.sh" module "$valid_module" module/other/v1.2.3
    expect_fail "$TOOLS_DIR/contract.sh" module "$valid_module" module/example-module/v1.2.3
    expect_fail "$TOOLS_DIR/contract.sh" module "$valid_module" module/example_module/v1.2.4
    expect_fail "$TOOLS_DIR/contract.sh" module "$valid_module" module/example_module/1.2.3
    expect_fail "$TOOLS_DIR/contract.sh" module "$wrong_dir" module/example_module/v1.2.3
    expect_pass "$TOOLS_DIR/contract.sh" cli iimod/v1.2.3 1.2.3
    expect_pass "$TOOLS_DIR/contract.sh" cli iimod/v1.2.3-rc.1 1.2.3-rc.1
    expect_fail "$TOOLS_DIR/contract.sh" cli iimod/v1.2.4 1.2.3
    expect_fail "$TOOLS_DIR/contract.sh" cli v1.2.3 1.2.3
    expect_fail "$TOOLS_DIR/contract.sh" cli iimod/v01.2.3 01.2.3
    expect_fail "$TOOLS_DIR/contract.sh" cli iimod/v1.2.3-01 1.2.3-01
    printf 'release contract tests passed: %d\n' "$PASS_COUNT"
}

main "$@"
