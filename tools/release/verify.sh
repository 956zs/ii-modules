#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TOOLS_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: tools/release/verify.sh RELEASE_DIR [RELEASE_TAG]

Dispatch verification for module/<id>/v<semver> or iimod/v<semver>.
EOF
}

infer_tag() {
    local release_dir="$1"
    local leaf parent grandparent
    leaf="$(basename "$release_dir")"
    parent="$(basename "$(dirname "$release_dir")")"
    grandparent="$(basename "$(dirname "$(dirname "$release_dir")")")"
    if [[ "$parent" == iimod ]]; then
        printf 'iimod/%s\n' "$leaf"
    elif [[ "$grandparent" == module ]]; then
        printf 'module/%s/%s\n' "$parent" "$leaf"
    else
        die "cannot infer release tag from: $release_dir"
    fi
}

main() {
    [[ "${1:-}" != -h && "${1:-}" != --help ]] || { usage; exit 0; }
    [[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 1; }
    local release_dir="$1"
    local release_tag="${2:-$(infer_tag "$release_dir")}"
    case "$release_tag" in
        module/*/v*) exec "$TOOLS_DIR/verify-module.sh" "$release_dir" "$release_tag" ;;
        iimod/v*) exec "$TOOLS_DIR/verify-cli.sh" "$release_dir" "$release_tag" ;;
        *) die "unsupported release tag: $release_tag" ;;
    esac
}

main "$@"
