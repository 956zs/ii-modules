#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
    cat <<'EOF'
Usage: tools/release/verify-cli.sh RELEASE_DIR [RELEASE_TAG]

Verify one CLI-only release. RELEASE_TAG is inferred from a canonical
dist/release/iimod/v<semver> path when omitted.
EOF
}

infer_tag() {
    local release_dir="$1"
    [[ "$(basename "$(dirname "$release_dir")")" == iimod ]] \
        || die "cannot infer CLI tag from: $release_dir"
    printf 'iimod/%s\n' "$(basename "$release_dir")"
}

main() {
    [[ "${1:-}" != -h && "${1:-}" != --help ]] || { usage; exit 0; }
    [[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 1; }
    for cmd in realpath sha256sum; do need_command "$cmd"; done

    local release_dir release_tag tag_version artifact_path version_output
    release_dir="$(absolute_path "$1")"
    [[ -d "$release_dir" ]] || die "release directory does not exist: $release_dir"
    release_tag="${2:-$(infer_tag "$release_dir")}"
    if [[ "$release_tag" =~ ^iimod/v($SEMVER_PATTERN)$ ]]; then
        tag_version="${BASH_REMATCH[1]}"
    else
        die "CLI tag must look like iimod/v1.2.3, got: $release_tag"
    fi
    artifact_path="$release_dir/$LINUX_BIN_NAME"
    verify_exact_output_files "$release_dir" "$LINUX_BIN_NAME"
    verify_single_artifact_checksum "$release_dir" "$LINUX_BIN_NAME"
    [[ -x "$artifact_path" ]] || die "CLI artifact is not executable: $artifact_path"
    version_output="$($artifact_path --version)"
    [[ "$version_output" == "iimod $tag_version" ]] \
        || die "CLI reports '$version_output', expected 'iimod $tag_version'"
    printf 'CLI release verified: %s\n' "$release_dir"
}

main "$@"
