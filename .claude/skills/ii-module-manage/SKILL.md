---
name: ii-module-manage
description: Install, review, upgrade, remove, and repair IIMP modules with iimod on an illogical-impulse (end-4 dots-hyprland) system. Enforces validate/check gates, Tier B consent, Lua-not-install-step policy, and post-update reapply.
---

# IIMP Module Manager

Operate modules only through `iimod`. Exit codes are the contract.

## Required Rules

1. Never hand-edit `~/.config/quickshell/ii/`, fenced IIMP regions, or
   `~/.local/share/iimp/` to install or repair modules.
2. Always run `iimod validate <source>` and `iimod check <source>` before
   `iimod install <source>`.
3. Do not install anything that fails validation, lint, package integrity,
   probes, dependency checks, or anchor checks.
4. Lua is not an install step. If a module ships Lua helpers, review them as
   source only; install only the generated payload/package after validate/check.
   Never execute third-party module Lua to make installation succeed.
5. Tier B modules require explicit user consent before `--allow-patches`.
   Before asking, read every patch file/op/anchor/content and review declared
   capabilities against code.
6. Probe failure is final incompatibility. There is no force install path.
7. After any dots-hyprland update or wipe warning, run `iimod reapply`.
8. Module updates go through `iimod update` (origin index, sha256-verified).
   A Tier B update re-requires `--allow-patches`; re-review its patches first
   as in rule 5. Never bypass update by hand-downloading into the shell tree.
8. Diagnose shell/module issues with `iimod doctor`, `iimod verify`, and the
   newest Quickshell log before changing state.
9. On this machine, manual IPC calls use
   `qs -c ii ipc --any-display ...`; `iimod` already handles this.
10. Do not use `pkill`/`killall` for Quickshell reloads. Use
    `qs -c ii ipc --any-display call iimp reload`.

## Exit Codes

| Code | Meaning | Action |
|---|---|---|
| 0 | OK | Report success. |
| 3 | Validation/lint failed | Do not install; report errors. |
| 4 | Probe failed | Incompatible; no bypass. |
| 5 | Dependency/conflict failed | Install dependency first or stop. |
| 6 | Integrity failed | Refuse package. |
| 7 | State error | Lock: wait; wiped: reapply; corrupt: doctor. |
| 8 | Anchor failed | Incompatible with this shell revision. |
| 9 | Tier B consent needed | Run Tier B consent review. |
| 10 | Protocol unsupported | Upgrade/downgrade `iimod`. |

## Playbooks

- Install/upgrade: `validate` -> `check` -> Tier B consent if needed ->
  `install` -> visual/log confirmation -> `verify`.
- Remove: `iimod uninstall <id>`; use `--cascade` only after user agrees to
  remove dependents.
- Post-update: `iimod reapply`; report any module marked incompatible.
- Enable/disable: `iimod enable <id>` / `iimod disable <id>` or Settings ->
  Modules.
- Bug report: include `iimod verify`, `iimod doctor`, module id/version, and the
  relevant Quickshell log lines.
