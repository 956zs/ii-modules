---
name: ii-module-author
description: Author IIMP v1 modules for the illogical-impulse (end-4 dots-hyprland) Quickshell config. Use when creating, editing, versioning, testing, or packaging an ii shell module. Enforces SPEC 1.0, QML payload rules, Lua-as-authoring-only policy, and iimod validation.
---

# IIMP Module Author

Author modules under IIMP SPEC 1.0. `iimod` is the reference tool and
`module.json` is the install contract.

## Required Rules

1. Start new modules with `iimod init <id>`.
2. Module ids match `^[a-z][a-z0-9_]{1,30}$`; no trailing `_`, no `__`, no
   hyphens. Reserved ids: `iimp`, `host`, `all`, `none`, `common`, `stock`,
   `settings`.
3. Keep every module file inside the payload directory. Never hand-edit
   `~/.config/quickshell/ii/` while authoring a module.
4. Runtime UI payload is QML. `bar.qml` roots a visual Item, preferably
   `BarGroup`; `main.qml` roots `Scope`, `PanelWindow`, or `LazyLoader`;
   `settings.qml` roots an Item/Layout fragment.
5. Direct `BarGroup` children must be visual `QQuickItem`s. Non-visual helpers
   such as `FileView`, `QtObject`, `Timer`, `Process`, `JsonAdapter`, and
   module-local components rooted in those types must live inside a visual
   `Item`/`MouseArea` or be exposed through properties.
6. `pragma Singleton` is forbidden. Instantiate logic objects in the entry
   component and pass instances down.
7. Any file using sibling module components must import its own directory with
   `import qs.mod.<id>`. Importing another module's `qs.mod.*` directory is
   forbidden; `requires.modules` is lifecycle dependency only, not QML sharing.
8. Store persistent options only in
   `~/.config/illogical-impulse/modules/<id>.json` using the ConfigLoader
   pattern. Never write module state into the shell's `config.json`.
   Never declare `property var` inside a `JsonAdapter`/`JsonObject`:
   Quickshell's deserializer segfaults writing a JSON object into it.
   Represent maps as a JSON string property and `JSON.parse` at the reader.
9. Probe every non-baseline stock API. Baseline APIs are `Config`, `Appearance`,
   `Directories`, `Translation`, `qs.modules.common`,
   `qs.modules.common.widgets`, and `qs.modules.common.functions`.
10. Declare capabilities honestly: `exec`, `network`, `filesystem-write`,
    `dbus`. Used but undeclared capabilities fail validation.
11. Prefer Tier A slot modules. Tier B patches are allowed only when slots
    cannot express the feature: insert-only, QML targets only, stock-text
    single-line anchors, no whole-file replacement, no fence-marker content.
12. Use strict semver. Breaking behavior/config changes bump major, additive
    features bump minor, fixes bump patch.
13. No `.qml` basename may collide with stock files under `$II/services/` or
    `$II/modules/common/**`.
14. User-visible text uses `Translation.tr("English source")`; runtime misses
    display that English source. Portable modules provide a complete, canonical
    `translations/zh_TW.json`; this repository also requires exact `zh_CN` and
    denies orphans in both first-party catalogs. Literal calls are preferred.
    Finite nonliteral calls require exact payload-root `i18n.sources.json`
    development metadata; it is not a manifest field and has no runtime role.
15. Lua is authoring glue only in IIMP v1. Lua may generate deterministic
    `module.json`/QML before packaging, but the packaged module must validate as
    static artifacts. Do not require `iimod` or Quickshell to execute
    module-supplied Lua at install time or runtime.
16. Module documentation follows the repository `AGENTS.md` Markdown template.
    Keep usage before internals; separate requirements, fallback behavior,
    configuration, data semantics, limitations, and implementation notes. Use
    tables for settings and backend matrices, and split paragraphs that contain
    three or more independent facts. Verify commands, paths, defaults,
    capabilities, tier, and version claims against `module.json` and source.
17. The feature owner owns QML/JS, English wording, dynamic-source provenance,
    manifest/version, README, and tests. Freeze source strings before delegating
    to an independent `ii-module-i18n` subagent. Do not ask that subagent to
    change feature files or weaken checks; resolve any ambiguity it returns.

## Release Checklist

Complete source and live verification first:

```bash
iimod validate <dir>
iimod suggest <dir>
iimod i18n extract <dir>
iimod i18n check <dir> --locale zh_TW --locale zh_CN --deny-orphans
iimod check <dir>
iimod install <dir>
qs -c ii ipc --any-display call iimp ping
# inspect shell log: no module ERROR/TypeError
iimod uninstall <id>
iimod verify
iimod install <dir>
```

Use the repository release entry point after the version bump is committed:

```bash
# Full local build + verification; never creates a tag
tools/release/publish.sh module <id>

# Only after merge to a clean, synchronized main
tools/release/publish.sh module <id> --push
```

Do not hand-create or push release tags when `publish.sh` is available. Never use
`--allow-dirty` with `--push`; GitHub Actions remains the only publisher of the
Release and canonical-origin package.

## Forbidden

- Shell edits outside `iimod`.
- Registry edits under `~/.local/share/iimp/`.
- `pkill`/`killall` reload workflows.
- Install hooks or Lua scripts that bypass `module.json` validation.
- Embedded copies of stock files.
