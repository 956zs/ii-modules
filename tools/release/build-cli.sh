#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ALLOW_DIRTY=0
RELEASE_TAG=""
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-60}"

usage() {
    cat <<'EOF'
Usage: tools/release/build-cli.sh [--allow-dirty] [RELEASE_TAG]

Build the iimod CLI release into dist/release/iimod/v<semver>.
RELEASE_TAG defaults to the exact tag at HEAD, or the Cargo package version.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --allow-dirty) ALLOW_DIRTY=1 ;;
            -h|--help) usage; exit 0 ;;
            -*) die "unknown option: $1" ;;
            *) [[ -z "$RELEASE_TAG" ]] || die "release tag provided more than once"; RELEASE_TAG="$1" ;;
        esac
        shift
    done
}

default_tag() {
    local head_tag
    head_tag="$(exact_head_tag)"
    [[ -z "$head_tag" ]] || { printf '%s\n' "$head_tag"; return; }
    printf 'iimod/v%s\n' "$(cargo_package_version)"
}

write_release_notes() {
    local output_dir="$1"
    local version="$2"
    cat > "$output_dir/RELEASE_NOTES.md" <<EOF
# $RELEASE_TAG

- Product: iimod CLI
- Version: $version
- Platform: Linux x86_64

Built with \`tools/release/build-cli.sh\` and verified with
\`tools/release/verify-cli.sh\`.
EOF
}

main() {
    parse_args "$@"
    for cmd in cargo git install python3 realpath sha256sum timeout; do need_command "$cmd"; done

    local cargo_version output_dir
    cargo_version="$(cargo_package_version)"
    RELEASE_TAG="${RELEASE_TAG:-$(default_tag)}"
    validate_cli_contract "$RELEASE_TAG" "$cargo_version"
    require_clean_tree "$ALLOW_DIRTY"
    output_dir="$(release_dir_for_tag "$RELEASE_TAG")"
    prepare_output_dir "$output_dir"

    cargo fmt --manifest-path "$IIMOD_MANIFEST" -- --check
    cargo clippy --manifest-path "$IIMOD_MANIFEST" --all-targets -- -D warnings
    timeout "$TEST_TIMEOUT_SECONDS" cargo test --manifest-path "$IIMOD_MANIFEST"
    cargo build --release --manifest-path "$IIMOD_MANIFEST"
    install -Dm755 "$IIMOD_BUILD_BIN" "$output_dir/$LINUX_BIN_NAME"
    write_release_notes "$output_dir" "$cargo_version"
    write_single_artifact_checksum "$output_dir" "$LINUX_BIN_NAME"
    verify_exact_output_files "$output_dir" "$LINUX_BIN_NAME"
    printf 'CLI release written to %s\n' "$output_dir"
}

main "$@"
