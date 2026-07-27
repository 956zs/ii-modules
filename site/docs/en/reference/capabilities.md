---
description: The four capability declarations in the capabilities field, how the lint detects them, and the security prompts shown at install time.
---

# Capabilities & Security

`capabilities` is a required manifest field (it can be `[]`) that **honestly declares what a module's code actually does**.

## The four capabilities

| Capability | Meaning | Lint detection (heuristic) |
| --- | --- | --- |
| `exec` | Executes an external program | `Process {`, `execDetached(`, `Hyprland.dispatch(` |
| `network` | Performs network I/O | `XMLHttpRequest`, `WebSocket`, `Socket` |
| `filesystem-write` | Writes to files other than its own config | `.setText(`, `writeAdapter(` (except the legitimate ConfigLoader pattern) |
| `dbus` | Accesses D-Bus | `DBus` |

## Lint verdicts

- **Used but not declared → validation fails (exit 3), install rejected**
- Declared but not detected → only a warning (over-declaring is always allowed)
- Read-only files (a FileView that never writes) need no capability at all

## This is not a sandbox

::: danger Informed consent ≠ isolation
The lint is a grep-level heuristic, and the spec says so explicitly. What it raises is the **bar for honesty** — making the declaration match the code — not runtime isolation. Once a module is installed into your shell, it holds the same privileges as the shell itself.

**Review a module's code before installing it.** This matters especially for Tier B modules (which modify stock files), which is why every install and update forces you to re-consent with `--allow-patches`.
:::

## Advice for module authors

- Use `iimod suggest` to auto-derive declarations, then confirm them by hand
- When in doubt, over-declare rather than under-declare
- Explain what each capability is for in your README (e.g. "exec: calls `nethogs` to get per-app traffic"), so users can make an informed decision
