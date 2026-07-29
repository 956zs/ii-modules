#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

WORK_DIR=""

usage() {
    cat <<'EOF'
Usage: tools/release/verify-module.sh RELEASE_DIR [RELEASE_TAG]

Verify one module-only release. RELEASE_TAG is inferred from a canonical
dist/release/module/<id>/v<semver> path when omitted.
EOF
}

cleanup() {
    if [[ -n "$WORK_DIR" && "$WORK_DIR" == /tmp/ii-module-verify.* ]]; then
        rm -rf "$WORK_DIR"
    fi
}

infer_tag() {
    local release_dir="$1"
    local version_part module_id product_part
    version_part="$(basename "$release_dir")"
    module_id="$(basename "$(dirname "$release_dir")")"
    product_part="$(basename "$(dirname "$(dirname "$release_dir")")")"
    [[ "$product_part" == module ]] || die "cannot infer module tag from: $release_dir"
    printf 'module/%s/%s\n' "$module_id" "$version_part"
}

main() {
    [[ "${1:-}" != -h && "${1:-}" != --help ]] || { usage; exit 0; }
    [[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 1; }
    for cmd in cargo mktemp python3 realpath sha256sum; do need_command "$cmd"; done

    local release_dir release_tag tag_id tag_version artifact_name artifact_path
    release_dir="$(absolute_path "$1")"
    [[ -d "$release_dir" ]] || die "release directory does not exist: $release_dir"
    release_tag="${2:-$(infer_tag "$release_dir")}"
    if [[ "$release_tag" =~ ^module/([^/]+)/v($SEMVER_PATTERN)$ ]]; then
        tag_id="${BASH_REMATCH[1]}"
        tag_version="${BASH_REMATCH[2]}"
    else
        die "module tag must look like module/<id>/v1.2.3, got: $release_tag"
    fi
    artifact_name="$tag_id-$tag_version.iimod"
    artifact_path="$release_dir/$artifact_name"
    verify_exact_output_files "$release_dir" "$artifact_name"
    verify_single_artifact_checksum "$release_dir" "$artifact_name"

    python3 - "$artifact_path" "$tag_id" "$tag_version" "$CANONICAL_MODULE_ORIGIN" <<'PY'
import json
import pathlib
import tarfile
import sys

package = pathlib.Path(sys.argv[1])
expected_id, expected_version, expected_origin = sys.argv[2:]
with tarfile.open(package, "r:gz") as archive:
    names = set(archive.getnames())
    manifest_path = f"{expected_id}/module.json"
    if manifest_path not in names:
        raise SystemExit(f"package missing {manifest_path}")
    manifest_file = archive.extractfile(manifest_path)
    integrity_file = archive.extractfile("integrity.json")
    if manifest_file is None or integrity_file is None:
        raise SystemExit("package metadata is unreadable")
    manifest = json.load(manifest_file)
    integrity = json.load(integrity_file)
if manifest.get("id") != expected_id:
    raise SystemExit("package manifest id does not match release tag")
if manifest.get("version") != expected_version:
    raise SystemExit("package manifest version does not match release tag")
if integrity.get("origin") != expected_origin:
    raise SystemExit("package origin is not the canonical module index")
PY

    [[ -x "$IIMOD_BUILD_BIN" ]] || cargo build --release --manifest-path "$IIMOD_MANIFEST"
    [[ -d "$FIXTURE_II_ROOT" ]] || die "missing fixture II root: $FIXTURE_II_ROOT"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-module-verify.XXXXXX")"
    trap cleanup EXIT
    "$IIMOD_BUILD_BIN" validate "$artifact_path"
    "$IIMOD_BUILD_BIN" i18n check "$artifact_path" --locale zh_TW --locale zh_CN --deny-orphans
    run_with_fixture "$WORK_DIR" package "$IIMOD_BUILD_BIN" check "$artifact_path"
    printf 'module release verified: %s\n' "$release_dir"
}

main "$@"
