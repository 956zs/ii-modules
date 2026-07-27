---
description: A complete module development tutorial, from iimod init scaffolding through passing validate/check.
---

# Develop Your First Module

This page walks you from scaffolding to an installable module. For the complete specification, treat [SPEC-1.0.md](https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md) as authoritative.

## Create the scaffold

```bash
iimod init my_widget
```

This produces the following directory layout (the payload tree **is** the installed tree — there's no destination mapping):

```
my_widget/
  module.json                 # manifest — required
  bar.qml                     # bar slot entry point (if slots includes "bar")
  main.qml                    # window slot entry point (if slots includes "window")
  settings.qml                # optional: settings fragment (Item root)
  ConfigLoader.qml            # scaffolded config-persistence template
  translations/<locale>.json  # optional: flat key→string dictionary
  README.md                   # recommended
```

## QML rules (important)

These rules are enforced by `iimod validate`; violating them causes an outright rejection:

- The root of `bar.qml` **must be a visual Item** (loaded by a QtQuick `Loader`).
- The root of `main.qml` **must be `Scope`, `PanelWindow`, or `LazyLoader`** (instantiated via `Qt.createComponent`, managing its own window).
- `.qml` filenames **must not** collide with any file under `$II/services/` or `$II/modules/common/**` (QML's same-directory type resolution would shadow the stock singleton).
- `pragma Singleton` is **forbidden** inside a module; instantiate a plain logic object in the entry component and pass it down instead.
- When referencing a sibling component in your own directory, you must explicitly `import qs.mod.<own-id>` (path-loaded files have no implicit same-directory resolution). **Importing another module's directory is forbidden.**

### Config persistence

Do not write to `~/.config/illogical-impulse/config.json` (the shell's JsonAdapter wipes out undeclared keys). Store your module's own options at `~/.config/illogical-impulse/modules/<id>.json`, using the scaffolded `ConfigLoader.qml` (FileView + JsonAdapter, with watchChanges + debounced writes).

## Probes and capabilities

ii has no version number, so compatibility relies on **probes**: declare that a stock file you depend on exists, or that it contains a given literal string. The baseline (`Config`/`Appearance`/`Directories` under `qs.modules.common`, widgets, functions, `qs.services.Translation`) needs no probe — **every other stock dependency must be covered by one**.

`capabilities` are honest declarations: `exec` / `network` / `filesystem-write` / `dbus`, cross-checked by a static lint — using one without declaring it fails validation outright (exit 3).

Both can be inferred by the tool first:

```bash
iimod suggest my_widget/    # auto-suggest probes and capabilities
```

## Development loop

```bash
iimod validate my_widget/   # manifest, layout, lint
iimod check    my_widget/   # probes + dependencies + anchor dry run
iimod install  my_widget/   # install on the real desktop to see it in action (transactional, rolls back automatically on failure)
```

Version numbers use strict semver (`X.Y.Z[-pre]`). Bump whatever changed: patch for bug fixes, minor for new features, major for breaking compatibility.

## Reference implementations

- [`modules/network_traffic/`](https://github.com/956zs/ii-modules/tree/main/modules/network_traffic) — a fully-featured bar module, documented file by file
- [`examples/hello_window/`](https://github.com/956zs/ii-modules/tree/main/examples/hello_window) — a minimal window example

::: tip Developing with an AI agent?
The repo's `.claude/skills/` ships two project skills (`ii-module-author`, `ii-module-manage`) so Claude Code automatically follows this protocol's discipline within the project.
:::

Once you're done, next up: [Publish & List](/en/guide/publish).
