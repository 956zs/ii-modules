---
description: IIMP is the community module protocol for the illogical-impulse Quickshell desktop — make, share, and install shell modules safely, with versioning, compatibility checks, and transactional installs.
---

# What is IIMP?

**IIMP (illogical-impulse Module Protocol)** is a **rigorous community module protocol** for [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)'s "illogical-impulse" Quickshell desktop: it lets enthusiasts safely build, share, and install each other's shell modules (bar widgets, floating window panels), with full versioning, compatibility checks, dependency management, and transactional installs.

## Why a protocol?

Before a protocol existed, community modules on the ii desktop were in rough shape:

- A dots-hyprland update runs `rsync --delete` across the entire shell tree — **manually installed modules simply vanish**.
- ii itself carries no version markers, so a module has no way to know which version it's compatible with.
- Hand-rolled patches fight each other — installing A, then B, often breaks both.

IIMP solves this systematically with three mechanisms:

| Mechanism | What it solves |
| --- | --- |
| **Feature probes** | ii has no version number, so IIMP verifies "file exists / contains a literal string" directly to confirm API-surface compatibility |
| **Fence-based reassembly engine** | All patches live inside fenced comments and are recomputed from a clean base every time, so install order never affects the outcome |
| **Store** | Full state lives in `~/.local/share/iimp/` (outside rsync's cleanup scope); `iimod reapply` can rebuild everything at any time |

## Two kinds of modules

- **Tier A (slot modules)** — plain folders loaded into a bar/window slot, with zero stock modifications. If one breaks, at most that slot goes blank; the rest of the desktop is unaffected.
- **Tier B (patch modules)** — modify stock files via structured, insert-only patches. Installing one requires explicit opt-in with `--allow-patches`.

## Decentralized updates

There is no central repository. Each `.iimod` embeds its own update source (a static `index.json`, hosted at any HTTPS location); once installed, `iimod update` can track new versions. The listing at [ii.n1cat.xyz](https://ii.n1cat.xyz/) is just an index — version information always comes straight from each module's own origin.

## Where to start?

- Want to **install a module** → [Install & Quick Start](/en/guide/install)
- Want to **write your own** → [Develop Your First Module](/en/guide/develop)
- Want the **full spec** → [SPEC-1.0.md](https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md)

::: warning Informed consent, not a sandbox
`capabilities` declarations (exec/network/filesystem-write/dbus) are cross-checked by a static lint, but that raises the bar for honesty — it is not a sandbox. Review a module's code before installing it. See [Capabilities & Security](/en/reference/capabilities) for details.
:::
