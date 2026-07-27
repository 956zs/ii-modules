---
description: The IIMP glossary on one page — Tier A/B, slots, manifest, probes, federated updates.
---

# Core Concepts

The IIMP glossary, on one page. For deeper detail, read [SPEC-1.0.md](https://github.com/956zs/ii-modules/blob/main/spec/SPEC-1.0.md).

## Tier A: slot modules

Plain folders loaded into a **bar** or **window** slot, with **zero stock modifications**. If a module breaks, at most that slot goes blank — the rest of the desktop is unaffected. The payload tree is the installed tree, living at `$II/mod/<id>/`.

## Tier B: patch modules

Modify stock files via **structured, insert-only patches**. A manifest with a non-empty `patches` field is Tier B; both installing and every subsequent update require explicit consent via `--allow-patches`.

## Probes

ii has no version number, so IIMP doesn't guess versions — it verifies the API surface directly:

- `file_exists`: a given stock file exists
- `file_contains`: a given stock file contains a literal string

A probe failure is an **absolute block** (exit 4): the stock API surface has changed, and the module should not be installed. The baseline (`qs.modules.common`, etc.) needs no probe; every other stock dependency must be declared.

## Fence-based reassembly engine

All Tier B patches are wrapped in fenced comments:

```
// >>> iimp <module-id>/<n> >>>
…inserted content…
// <<< iimp <module-id>/<n> <<<
```

Whenever any module is installed or removed, the engine **recomputes every patch from a clean base** — so install order never affects the outcome, patches never conflict with each other, and removing a module never leaves residue behind.

## Store

The full install state (module payloads, the clean stock base, the registry) lives in `~/.local/share/iimp/` — **outside** the scope of dots-hyprland's `rsync --delete` cleanup. `iimod reapply` can rebuild everything in the shell tree from the store at any time.

## Federated updates (origin)

There is no central repository. Each module remembers its own update source (a static `index.json`, at any HTTPS location). `iimod update` checks each module's own source individually; downloads are always verified against sha256. The [module directory site](https://ii.n1cat.xyz/) is just an index — version information comes directly from each module's origin.

## Capabilities

A module must honestly declare what its code actually does: `exec` / `network` / `filesystem-write` / `dbus`. This is cross-checked by a static lint — using one without declaring it causes the install to be rejected outright. See [Capabilities & Security](/en/reference/capabilities) for details.
