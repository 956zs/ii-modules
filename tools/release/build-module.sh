#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ALLOW_DIRTY=0
MODULE_DIR=""
RELEASE_TAG=""
WORK_DIR=""

usage() {
    cat <<'EOF'
Usage: tools/release/build-module.sh [--allow-dirty] MODULE_DIR [RELEASE_TAG]

Build one module release into dist/release/module/<id>/v<semver>.
RELEASE_TAG defaults to the exact tag at HEAD, or the module manifest version.
EOF
}

cleanup() {
    if [[ -n "$WORK_DIR" && "$WORK_DIR" == /tmp/ii-module-release.* ]]; then
        rm -rf "$WORK_DIR"
    fi
}

parse_args() {
    while (($#)); do
        case "$1" in
            --allow-dirty) ALLOW_DIRTY=1 ;;
            -h|--help) usage; exit 0 ;;
            -*) die "unknown option: $1" ;;
            *)
                if [[ -z "$MODULE_DIR" ]]; then
                    MODULE_DIR="$1"
                elif [[ -z "$RELEASE_TAG" ]]; then
                    RELEASE_TAG="$1"
                else
                    die "too many arguments"
                fi
                ;;
        esac
        shift
    done
    [[ -n "$MODULE_DIR" ]] || { usage >&2; exit 1; }
    MODULE_DIR="$(absolute_path "$MODULE_DIR")"
}

default_tag() {
    local head_tag manifest_id manifest_version
    head_tag="$(exact_head_tag)"
    [[ -z "$head_tag" ]] || { printf '%s\n' "$head_tag"; return; }
    manifest_id="$(module_json_field "$MODULE_DIR/module.json" id)"
    manifest_version="$(module_json_field "$MODULE_DIR/module.json" version)"
    printf 'module/%s/v%s\n' "$manifest_id" "$manifest_version"
}

write_release_notes() {
    local output_dir="$1"
    local module_id="$2"
    local module_version="$3"
    cat > "$output_dir/RELEASE_NOTES.md" <<EOF
# $RELEASE_TAG

- Module: $module_id
- Version: $module_version
- Origin: $CANONICAL_MODULE_ORIGIN

Built with \`tools/release/build-module.sh\` and verified with
\`tools/release/verify-module.sh\`.
EOF
}

main() {
    parse_args "$@"
    for cmd in cargo git mktemp python3 realpath sha256sum; do need_command "$cmd"; done
    require_module_path "$MODULE_DIR"
    RELEASE_TAG="${RELEASE_TAG:-$(default_tag)}"
    validate_module_contract "$MODULE_DIR" "$RELEASE_TAG"
    require_clean_tree "$ALLOW_DIRTY"
    [[ -d "$FIXTURE_II_ROOT" ]] || die "missing fixture II root: $FIXTURE_II_ROOT"

    local output_dir module_id module_version artifact_name artifact_path
    output_dir="$(release_dir_for_tag "$RELEASE_TAG")"
    module_id="$(module_json_field "$MODULE_DIR/module.json" id)"
    module_version="$(module_json_field "$MODULE_DIR/module.json" version)"
    artifact_name="$module_id-$module_version.iimod"
    artifact_path="$output_dir/$artifact_name"
    prepare_output_dir "$output_dir"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-module-release.XXXXXX")"
    trap cleanup EXIT

    cargo build --release --manifest-path "$IIMOD_MANIFEST"
    "$IIMOD_BUILD_BIN" validate "$MODULE_DIR"
    run_with_fixture "$WORK_DIR" module-dir "$IIMOD_BUILD_BIN" check "$MODULE_DIR"
    "$IIMOD_BUILD_BIN" pack --out "$artifact_path" --origin "$CANONICAL_MODULE_ORIGIN" "$MODULE_DIR"
    "$IIMOD_BUILD_BIN" validate "$artifact_path"
    run_with_fixture "$WORK_DIR" module-package "$IIMOD_BUILD_BIN" check "$artifact_path"
    write_release_notes "$output_dir" "$module_id" "$module_version"
    write_single_artifact_checksum "$output_dir" "$artifact_name"
    verify_exact_output_files "$output_dir" "$artifact_name"
    printf 'module release written to %s\n' "$output_dir"
}

main "$@"
