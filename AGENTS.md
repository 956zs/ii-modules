# AGENTS.md

## Start Here

- Read `README.md` and the target module's `README.md` before editing.
- Use `.claude/skills/ii-module-author/SKILL.md` for module development and
  `.claude/skills/ii-module-manage/SKILL.md` for live module operations.
- Keep `.claude/skills/<name>/SKILL.md` and `skills/<name>/SKILL.md` identical.
  Update both whenever workflow or product rules change.
- Record cross-session progress in `plans/SESSION.md` and unresolved issues in
  `plans/ISSUES.md`.

## Markdown Documentation

Apply these rules whenever an agent creates or edits Markdown in this repository.
For module documentation, read the current `module.json`, relevant entry QML, and
existing README before writing; documentation must describe the checked-in
behavior rather than plans or remembered behavior.

### Module README Template

Use this order and omit only sections that genuinely do not apply:

1. `# <module id or product name> - <short purpose>`
2. A two- or three-sentence summary that states the tier, primary value, and
   important scope boundary
3. A warning or important callout for experimental status, privileges, or
   destructive/migration concerns
4. `## Features` or `## Interaction`
5. `## Requirements` for system dependencies, capabilities, and ordered
   fallback behavior
6. `## Installation` with commands runnable from the repository root
7. `## Configuration` with the settings path and a key/default/description table
8. `## Data and behavior` for persistence, accounting, privacy, or lifecycle
   semantics
9. `## Limitations` with explicit unsupported or best-effort behavior
10. `## Implementation notes` for maintainers, followed by `## Development` when
    module-specific verification commands are useful

### Style and Quality

- Put user-facing usage before maintainer internals. Keep one concept per
  paragraph and prefer paragraphs of no more than three sentences.
- Replace dense prose containing three or more independent facts with a table,
  bullets, or focused subsections. Use tables for operations, settings,
  dependencies/backends, and compatibility matrices.
- Keep requirements, current behavior, limitations, migration notes, and
  implementation details separate. Do not mix release history into the current
  behavior description; use a dedicated migration note only when users must act.
- State fallback order and degraded behavior explicitly. Never hide security,
  privilege, data-loss, coverage, or compatibility limits in an implementation
  paragraph.
- Use sentence-case headings, fenced code blocks with a language tag, backticks
  for paths/commands/keys, and repository-relative links. Do not use manual line
  breaks, decorative separators, or a hand-written table of contents for a short
  README.
- Wrap prose at roughly 80-100 columns when practical, keep table cells concise,
  and use the repository's established language for that document.
- Verify every command, path, default, dependency, capability, tier, and version
  claim against source. Run `git diff --check` and the available Markdown/link
  checks before completion.

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
