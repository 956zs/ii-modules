# AGENTS.md

## Start Here

- Read `README.md` and the target module's `README.md` before editing.
- Use `.claude/skills/ii-module-author/SKILL.md` for module development and
  `.claude/skills/ii-module-manage/SKILL.md` for live module operations.
- Keep `.claude/skills/<name>/SKILL.md` and `skills/<name>/SKILL.md` identical.
  Update both whenever workflow or product rules change.
- Record cross-session progress in `plans/SESSION.md` and unresolved issues in
  `plans/ISSUES.md`.

## Release

Use the single release entry point. It derives the tag from `module.json` or
`tools/iimod/Cargo.toml`, builds, and verifies before any publication:

```bash
tools/release/publish.sh module <id>        # local dry-run
tools/release/publish.sh cli                # local dry-run
tools/release/publish.sh module <id> --push # clean synchronized main only
tools/release/publish.sh cli --push         # clean synchronized main only
```

Do not manually create release tags when this helper is available. Never combine
`--allow-dirty` with `--push`. GitHub Actions is the only publisher of GitHub
Releases and canonical-origin module packages.

## Multi-Agent Live Operations

Assign exactly one agent as the live mutation owner. Only that agent may run
`install`, `uninstall`, `enable`, `disable`, `repair`, `reapply`, or `update`.
Other agents may run read-only checks, builds, package validation, and log
inspection.

`iimod` 1.2.0+ stores an immutable, monotonic host generation outside the shell
wipe zone. Its first mutating command also installs a permanent legacy lock
fence, so older binaries fail before they can rewrite host assets. If a PATH
binary reports `another iimod is running (pid 1)`, upgrade to the current
`iimod`; do not delete `~/.local/share/iimp/lock` or bypass the fence.

New mutators still use a fail-fast `mutation.lock.v2`, so the single live
mutation owner rule remains required until bounded/FIFO waiting ships. An older
freshness-aware binary may install modules while preserving a newer durable host
generation; a same-generation content collision or corrupt generation bundle
must fail closed.
