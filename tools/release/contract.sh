#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
    cat <<'EOF'
Usage:
  tools/release/contract.sh module MODULE_DIR RELEASE_TAG
  tools/release/contract.sh cli RELEASE_TAG CARGO_VERSION

Validate release tag metadata without building artifacts.
EOF
}

main() {
    case "${1:-}" in
        module)
            [[ $# -eq 3 ]] || { usage >&2; exit 1; }
            validate_module_contract "$2" "$3"
            ;;
        cli)
            [[ $# -eq 3 ]] || { usage >&2; exit 1; }
            validate_cli_contract "$2" "$3"
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
