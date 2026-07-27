---
description: Day-to-day commands once modules are installed — list, update, disable, remove, and troubleshoot.
---

# Daily Use & Updates

Once modules are installed, here are the commands you'll reach for regularly.

## Common commands

```bash
iimod list              # installed modules, versions, and status
iimod info <id>         # detailed info for a single module
iimod enable <id>       # enable
iimod disable <id>      # disable (does not uninstall)
iimod verify            # check install state and file integrity
iimod remove <id>       # uninstall
```

## Updating modules

IIMP updates are **federated**: there is no central repository — each module remembers its own source (origin) at install time.

```bash
iimod update --dry-run   # only check what's new, don't touch anything
iimod update              # update everything
```

Updates go through the same transactional pipeline as installs:

- Downloads are always verified against `sha256`; a mismatch exits with `6` and the file is never written to disk
- Failures roll back automatically; module settings are preserved and the origin carries over
- **Tier B modules** require re-passing `--allow-patches` on update (the new version's patches may differ)

### How is the origin determined?

The origin is a static `index.json` hosted at any HTTPS location (GitHub Releases, raw, self-hosted — all work). Priority order:

1. The `--origin <url>` flag (can always explicitly override)
2. The origin embedded in the `.iimod` (official release packages embed one, produced by `pack --origin`)
3. When installing from a URL, iimod automatically remembers the `index.json` in the same directory

Transport uses the system `curl`, and only `https://` and `file://` are allowed (the latter for LAN sharing and offline testing).

## After a dots-hyprland update: reapply

::: danger Must run
A dots-hyprland update runs `rsync --delete` across the entire shell tree. After updating the desktop, run:

```bash
iimod reapply
```

All modules and patches are rebuilt in one batch from the store (`~/.local/share/iimp/`).
:::

## When something goes wrong

`iimod`'s exit codes are a stable contract, each with a fixed meaning (probe failure, dependency conflict, integrity mismatch, ...), making it easy to script around and report issues. See [Exit codes](/en/reference/exit-codes) for the full reference.
