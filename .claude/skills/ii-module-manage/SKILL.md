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
11. During multi-agent work, assign one live mutation owner. Other agents may
    validate, check, pack, and inspect logs, but must not run install, uninstall,
    enable, disable, repair, reapply, or update concurrently.
12. `iimod` 1.2.0+ persists a monotonic host generation and permanently fences
    legacy mutators. If an older PATH binary reports `another iimod is running
    (pid 1)`, upgrade `iimod`; never delete `~/.local/share/iimp/lock` or bypass
    it. A missing/corrupt host generation or same-generation content collision
    is a hard state error, not a reason to force an install.
13. New mutators still use a fail-fast `mutation.lock.v2`; keep exactly one live
    mutation owner until bounded/FIFO waiting ships. Freshness-aware older
    binaries preserve the selected newer host bundle during module operations.
14. Finish every management or release task with explicit workspace hygiene. Run
    `git status --short --branch`, classify every changed path, remove generated
    or temporary output, and commit completed repository changes to a task
    branch. If the user requested publication, push the branch and complete the
    normal PR or release flow. Never commit or push unrelated pre-existing or
    user-owned paths; report any remaining paths and why they remain.

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
- Release cleanup: after a clean temporary release worktree publishes
  successfully, reconcile the original development worktree with the updated
  `origin/main` when this can be done without discarding local work; report the
  exact blocking paths if it cannot.
