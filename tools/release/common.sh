#!/usr/bin/env bash

RELEASE_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$RELEASE_TOOLS_DIR/../.." && pwd)"
DIST_DIR="${RELEASE_DIST_DIR:-$ROOT_DIR/dist/release}"
IIMOD_MANIFEST="$ROOT_DIR/tools/iimod/Cargo.toml"
IIMOD_BUILD_BIN="$ROOT_DIR/tools/iimod/target/release/iimod"
FIXTURE_II_ROOT="$ROOT_DIR/spec/fixtures/ii-stock"
LINUX_BIN_NAME="iimod-linux-x86_64"
CANONICAL_MODULE_ORIGIN="https://ii.n1cat.xyz/index.json"
SEMVER_PATTERN='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?'

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

module_json_field() {
    local manifest="$1"
    local field="$2"
    python3 - "$manifest" "$field" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
value = manifest.get(sys.argv[2])
if not isinstance(value, str) or not value:
    raise SystemExit(f"manifest field {sys.argv[2]!r} must be a non-empty string")
print(value)
PY
}

cargo_package_version() {
    cargo metadata --no-deps --manifest-path "$IIMOD_MANIFEST" --format-version=1 \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["packages"][0]["version"])'
}

validate_module_contract() {
    local module_dir="$1"
    local release_tag="$2"
    local manifest="$module_dir/module.json"
    local tag_id tag_version manifest_id manifest_version

    [[ -f "$manifest" ]] || die "missing module manifest: $manifest"
    if [[ "$release_tag" =~ ^module/([^/]+)/v($SEMVER_PATTERN)$ ]]; then
        tag_id="${BASH_REMATCH[1]}"
        tag_version="${BASH_REMATCH[2]}"
    else
        die "module tag must look like module/<id>/v1.2.3, got: $release_tag"
    fi

    manifest_id="$(module_json_field "$manifest" id)"
    manifest_version="$(module_json_field "$manifest" version)"
    [[ "$tag_id" =~ ^[a-z][a-z0-9_]{1,30}$ && "$tag_id" != *_ && "$tag_id" != *__* ]] \
        || die "module tag id '$tag_id' is not a valid IIMP module id"
    [[ "$tag_id" == "$manifest_id" ]] \
        || die "module tag id '$tag_id' does not match manifest id '$manifest_id'"
    [[ "$tag_version" == "$manifest_version" ]] \
        || die "module tag version '$tag_version' does not match manifest version '$manifest_version'"
    [[ "$(basename "$module_dir")" == "$manifest_id" ]] \
        || die "module directory name '$(basename "$module_dir")' does not match manifest id '$manifest_id'"
}

validate_cli_contract() {
    local release_tag="$1"
    local cargo_version="$2"
    local tag_version

    if [[ "$release_tag" =~ ^iimod/v($SEMVER_PATTERN)$ ]]; then
        tag_version="${BASH_REMATCH[1]}"
    else
        die "CLI tag must look like iimod/v1.2.3, got: $release_tag"
    fi
    [[ "$tag_version" == "$cargo_version" ]] \
        || die "CLI tag version '$tag_version' does not match Cargo version '$cargo_version'"
}

require_module_path() {
    local module_dir="$1"
    local modules_dir="$ROOT_DIR/modules"
    local resolved_module resolved_modules
    resolved_module="$(realpath "$module_dir")"
    resolved_modules="$(realpath "$modules_dir")"
    [[ "$(dirname "$resolved_module")" == "$resolved_modules" ]] \
        || die "module must be a direct child of $modules_dir: $module_dir"
}

require_clean_tree() {
    local allow_dirty="$1"
    ((allow_dirty == 1)) && return
    git -C "$ROOT_DIR" diff --quiet || die "working tree has unstaged changes"
    git -C "$ROOT_DIR" diff --cached --quiet || die "working tree has staged changes"
    [[ -z "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]] \
        || die "working tree has untracked files"
}

exact_head_tag() {
    git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || true
}

release_dir_for_tag() {
    printf '%s/%s\n' "$DIST_DIR" "$1"
}

absolute_path() {
    realpath -m "$1"
}

prepare_output_dir() {
    local output_dir="$1"
    [[ ! -e "$output_dir" ]] || die "output already exists: $output_dir"
    mkdir -p "$(dirname "$output_dir")" "$output_dir"
}

write_single_artifact_checksum() {
    local output_dir="$1"
    local artifact_name="$2"
    (cd "$output_dir" && sha256sum "$artifact_name" > SHA256SUMS)
}

verify_exact_output_files() {
    local output_dir="$1"
    local artifact_name="$2"
    python3 - "$output_dir" "$artifact_name" <<'PY'
import pathlib
import sys

directory = pathlib.Path(sys.argv[1])
expected = {sys.argv[2], "SHA256SUMS", "RELEASE_NOTES.md"}
actual = {path.name for path in directory.iterdir()}
if actual != expected:
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    raise SystemExit(f"release contents mismatch; missing={missing}, extra={extra}")
if not all(path.is_file() and not path.is_symlink() for path in directory.iterdir()):
    raise SystemExit("release output must contain regular files only")
PY
}

verify_single_artifact_checksum() {
    local output_dir="$1"
    local artifact_name="$2"
    local checksum_entry
    checksum_entry="$(cd "$output_dir" && sha256sum -c SHA256SUMS)"
    [[ "$checksum_entry" == "$artifact_name: OK" ]] \
        || die "SHA256SUMS must contain exactly $artifact_name"
}

run_with_fixture() {
    local work_dir="$1"
    local state_name="$2"
    shift 2
    IIMOD_II_ROOT="$FIXTURE_II_ROOT" \
        IIMOD_STATE_ROOT="$work_dir/state-$state_name" \
        IIMOD_SHELLCONFIG_ROOT="$work_dir/shellconfig" \
        IIMOD_NO_QS=1 \
        "$@"
}
