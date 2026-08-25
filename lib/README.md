# lib - golden masters for vendored module infrastructure

IIMP modules are self-contained: they may not import each other's files, so
shared infrastructure is vendored (copied) into every module payload. This
directory holds the canonical versions. Fix bugs here first, then propagate to
module copies; the drift checker keeps copies from silently diverging on the
invariants that matter.

## Contents

| File | Purpose |
|---|---|
| `ConfigLoader.template.qml` | Canonical simple config persistence skeleton (FileView + JsonAdapter) |

Two ConfigLoader variants exist in the wild:

- **Simple** (the template here): watch + materialize + owner-writes-defaults.
  Right for modules whose config only changes from the settings page.
- **Owner-elected intent queue** (`modules/network_traffic/ConfigLoader.qml`):
  for modules that persist runtime accounting from multiple surfaces and must
  serialize writes through one elected owner via IPC intents.

## Drift checking

```bash
node tools/lib-sync/check-configloader.mjs
```

The checker does not require byte-identical copies; module schemas legitimately
differ. It verifies skeleton invariants on every `modules/*/ConfigLoader.qml`:

- `watchChanges: true`, `blockWrites: true`, `atomicWrites: true`
- a materialization (or internal-reload) guard around the reload/write echo
- `onLoadFailed` materializes defaults only for `FileNotFound`
- a `ready` flag
- `path` targets `Directories.shellConfig + "/modules/<module id>.json"`
- no `property var` inside the `JsonAdapter`

Intentional deviations are declared per module and per rule in
`tools/lib-sync/allowlist.json` with a reason; undeclared deviations fail CI.

## Scaffolding

`iimod init` emits this ConfigLoader skeleton in new modules. When the
template changes, update `tools/iimod/src/commands.rs` (`cmd_init`) to match.
