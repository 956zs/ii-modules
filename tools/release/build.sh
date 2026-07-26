#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
IIMOD_MANIFEST="$ROOT_DIR/tools/iimod/Cargo.toml"
IIMOD_BIN="$ROOT_DIR/tools/iimod/target/release/iimod"
FIXTURE_II_ROOT="$ROOT_DIR/spec/fixtures/ii-stock"
MODULE_DIR="$ROOT_DIR/modules/network_traffic"
STARTER_NAME="ii-modules-starter"
LINUX_BIN_NAME="iimod-linux-x86_64"
STARTER_README_TEMPLATE="$ROOT_DIR/tools/release/starter.README.md.in"
TEST_TIMEOUT_SECONDS=60

ALLOW_DIRTY=0
RELEASE_TAG=""
WORK_DIR=""

usage() {
    cat <<'EOF'
Usage: tools/release/build.sh [--allow-dirty] [RELEASE_TAG]

Build release artifacts into dist/release/<RELEASE_TAG>.
RELEASE_TAG defaults to the exact git tag at HEAD, or v<network_traffic version>.

Options:
  --allow-dirty  Allow uncommitted source changes for local dry-runs.
  -h, --help     Show this help.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$WORK_DIR" && "$WORK_DIR" == /tmp/ii-modules-release.* ]]; then
        rm -rf "$WORK_DIR"
    fi
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

parse_args() {
    while (($#)); do
        case "$1" in
            --allow-dirty)
                ALLOW_DIRTY=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                [[ -z "$RELEASE_TAG" ]] || die "release tag provided more than once"
                RELEASE_TAG="$1"
                ;;
        esac
        shift
    done
}

module_json_field() {
    local manifest="$1"
    local field="$2"
    python3 - "$manifest" "$field" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)[sys.argv[2]])
PY
}

cargo_package_version() {
    cargo metadata --no-deps --manifest-path "$IIMOD_MANIFEST" --format-version=1 \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["packages"][0]["version"])'
}

module_package_name() {
    printf '%s-%s.iimod\n' \
        "$(module_json_field "$MODULE_DIR/module.json" id)" \
        "$(module_json_field "$MODULE_DIR/module.json" version)"
}

default_release_tag() {
    if git -C "$ROOT_DIR" describe --tags --exact-match >/dev/null 2>&1; then
        git -C "$ROOT_DIR" describe --tags --exact-match
        return
    fi
    printf 'v%s\n' "$(module_json_field "$MODULE_DIR/module.json" version)"
}

validate_release_tag() {
    [[ "$RELEASE_TAG" =~ ^v[0-9]+(\.[0-9]+){2}([-.][0-9A-Za-z.-]+)?$ ]] \
        || die "release tag must look like v1.2.3, got: $RELEASE_TAG"
}

require_clean_tree() {
    ((ALLOW_DIRTY == 1)) && return
    git -C "$ROOT_DIR" diff --quiet || die "working tree has unstaged changes"
    git -C "$ROOT_DIR" diff --cached --quiet || die "working tree has staged changes"
    [[ -z "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]] \
        || die "working tree has untracked files"
}

prepare_environment() {
    for cmd in cargo git install mktemp python3 sha256sum tar timeout unzip zip; do
        need_command "$cmd"
    done
    [[ -d "$FIXTURE_II_ROOT" ]] || die "missing fixture II root: $FIXTURE_II_ROOT"
    [[ -f "$MODULE_DIR/module.json" ]] || die "missing module manifest: $MODULE_DIR/module.json"
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-modules-release.XXXXXX")"
    trap cleanup EXIT
}

release_dir() {
    printf '%s/%s\n' "$DIST_DIR" "$RELEASE_TAG"
}

prepare_release_dir() {
    local out_dir
    out_dir="$(release_dir)"
    [[ ! -e "$out_dir" ]] || die "output already exists: $out_dir"
    mkdir -p "$out_dir"
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

build_iimod() {
    cargo fmt --manifest-path "$IIMOD_MANIFEST" -- --check
    cargo clippy --manifest-path "$IIMOD_MANIFEST" --all-targets -- -D warnings
    cargo test --manifest-path "$IIMOD_MANIFEST" --no-run
    timeout "$TEST_TIMEOUT_SECONDS" cargo test --manifest-path "$IIMOD_MANIFEST"
    cargo build --release --manifest-path "$IIMOD_MANIFEST"
    install -Dm755 "$IIMOD_BIN" "$(release_dir)/$LINUX_BIN_NAME"
}

# Canonical update origin derived from the GitHub remote:
# https://github.com/<owner>/<repo>/releases/latest/download/index.json
# Empty when there is no recognizable remote (local dry-runs).
canonical_origin() {
    local remote
    remote="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    case "$remote" in
        git@github.com:*) remote="https://github.com/${remote#git@github.com:}" ;;
        https://github.com/*) ;;
        *) return 0 ;;
    esac
    remote="${remote%.git}"
    printf '%s/releases/latest/download/index.json\n' "$remote"
}

pack_module() {
    local package_path origin
    package_path="$(release_dir)/$(module_package_name)"
    origin="$(canonical_origin)"

    "$IIMOD_BIN" validate "$MODULE_DIR"
    run_with_fixture "module-dir-check" "$IIMOD_BIN" check "$MODULE_DIR"
    if [[ -n "$origin" ]]; then
        "$IIMOD_BIN" pack --out "$package_path" --origin "$origin" "$MODULE_DIR"
    else
        echo "note: no GitHub remote — packing without an embedded origin" >&2
        "$IIMOD_BIN" pack --out "$package_path" "$MODULE_DIR"
    fi
    "$IIMOD_BIN" validate "$package_path"
    run_with_fixture "module-package-check" "$IIMOD_BIN" check "$package_path"
    write_update_index "$package_path"
}

# Update index published next to the package. `iimod install <package-url>`
# records the sibling index.json automatically, so releases fetched from
# .../releases/latest/download/ get zero-config `iimod update`.
write_update_index() {
    local package_path="$1"
    python3 - "$MODULE_DIR/module.json" "$package_path" "$(release_dir)/index.json" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
package = pathlib.Path(sys.argv[2])
sha = hashlib.sha256(package.read_bytes()).hexdigest()
index = {
    "indexVersion": 1,
    "modules": {
        manifest["id"]: {
            "version": manifest["version"],
            "url": package.name,
            "sha256": sha,
        }
    },
}
pathlib.Path(sys.argv[3]).write_text(
    json.dumps(index, indent=2) + "\n", encoding="utf-8"
)
PY
}

write_starter_readme() {
    local readme_path="$1"
    local module_file="$2"
    python3 - "$STARTER_README_TEMPLATE" "$readme_path" "$module_file" <<'PY'
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
pathlib.Path(sys.argv[2]).write_text(
    template.replace("@MODULE_FILE@", sys.argv[3]),
    encoding="utf-8",
)
PY
}

build_source_tarball() {
    local starter_dir="$1"
    tar -C "$ROOT_DIR" \
        --exclude='./.git' \
        --exclude='./dist' \
        --exclude='./tools/iimod/target' \
        -czf "$starter_dir/src/ii-modules-source.tar.gz" .
}

build_starter_zip() {
    local out_dir starter_dir module_file starter_zip
    out_dir="$(release_dir)"
    starter_dir="$WORK_DIR/$STARTER_NAME"
    module_file="$(module_package_name)"
    starter_zip="$out_dir/${STARTER_NAME}-${RELEASE_TAG}.zip"

    mkdir -p "$starter_dir/bin" "$starter_dir/modules" "$starter_dir/spec"
    mkdir -p "$starter_dir/skills" "$starter_dir/.claude/skills" "$starter_dir/src"
    install -Dm755 "$IIMOD_BIN" "$starter_dir/bin/iimod"
    cp "$out_dir/$module_file" "$starter_dir/modules/$module_file"
    cp "$ROOT_DIR/spec/SPEC-1.0.md" "$starter_dir/spec/SPEC-1.0.md"
    cp -R "$ROOT_DIR/skills/ii-module-author" "$ROOT_DIR/skills/ii-module-manage" "$starter_dir/skills/"
    cp -R "$ROOT_DIR/.claude/skills/ii-module-author" "$ROOT_DIR/.claude/skills/ii-module-manage" "$starter_dir/.claude/skills/"
    build_source_tarball "$starter_dir"
    write_starter_readme "$starter_dir/README.md" "$module_file"
    (cd "$starter_dir" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
    (cd "$WORK_DIR" && zip -qr "$starter_zip" "$STARTER_NAME")
}

write_release_notes() {
    local module_id module_version iimod_version
    module_id="$(module_json_field "$MODULE_DIR/module.json" id)"
    module_version="$(module_json_field "$MODULE_DIR/module.json" version)"
    iimod_version="$(cargo_package_version)"
    cat > "$(release_dir)/RELEASE_NOTES.md" <<EOF
# $RELEASE_TAG

- iimod CLI: $iimod_version
- $module_id module: $module_version

Artifacts are built from this tag by \`tools/release/build.sh\` and verified by
\`tools/release/verify.sh\`.
EOF
}

write_checksums() {
    (cd "$(release_dir)" && \
        find . -maxdepth 1 -type f \
            ! -name SHA256SUMS \
            ! -name RELEASE_NOTES.md \
            -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
}

main() {
    parse_args "$@"
    RELEASE_TAG="${RELEASE_TAG:-$(default_release_tag)}"
    validate_release_tag
    require_clean_tree
    prepare_environment
    prepare_release_dir
    build_iimod
    pack_module
    build_starter_zip
    write_release_notes
    write_checksums
    printf 'release artifacts written to %s\n' "$(release_dir)"
}

main "$@"
