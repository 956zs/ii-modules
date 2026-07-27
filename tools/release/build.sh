#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLS_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: tools/release/build.sh [--allow-dirty] [RELEASE_TAG]

Dispatch a namespaced release tag to the module-only or CLI-only builder.
Supported tags: module/<id>/v<semver>, iimod/v<semver>.
EOF
}

main() {
    local allow_dirty=0 release_tag=""
    while (($#)); do
        case "$1" in
            --allow-dirty) allow_dirty=1 ;;
            -h|--help) usage; exit 0 ;;
            -*) die "unknown option: $1" ;;
            *) [[ -z "$release_tag" ]] || die "release tag provided more than once"; release_tag="$1" ;;
        esac
        shift
    done
    release_tag="${release_tag:-$(exact_head_tag)}"
    [[ -n "$release_tag" ]] || die "no exact tag at HEAD; use a product-specific builder or pass RELEASE_TAG"

    local dirty_args=()
    ((allow_dirty == 0)) || dirty_args+=(--allow-dirty)
    case "$release_tag" in
        module/*/v*)
            local module_id="${release_tag#module/}"
            module_id="${module_id%%/*}"
            exec "$TOOLS_DIR/build-module.sh" "${dirty_args[@]}" "$ROOT_DIR/modules/$module_id" "$release_tag"
            ;;
        iimod/v*) exec "$TOOLS_DIR/build-cli.sh" "${dirty_args[@]}" "$release_tag" ;;
        *) die "unsupported release tag: $release_tag" ;;
    esac
}

main "$@"
