---
description: Starting from scratch — install the iimod CLI, then install your first IIMP module.
---

# Install & Quick Start

This page walks you through it from scratch: get the `iimod` CLI installed, then install your first module.

## Prerequisites

- The **illogical-impulse** Quickshell desktop from [dots-hyprland](https://github.com/end-4/dots-hyprland) already installed
- Linux x86_64 (for other architectures, see [Building from Source](#building-from-source))

## Install the iimod CLI

Download the official binary from GitHub Releases:

```bash
curl -fsSL -o iimod https://github.com/956zs/ii-modules/releases/latest/download/iimod-linux-x86_64 && chmod +x iimod && sudo install iimod /usr/local/bin/iimod
```

::: tip Verify the sha256
Every release ships a `SHA256SUMS` file. After downloading, verify with `sha256sum -c` to confirm the binary hasn't been tampered with.
:::

### Building from Source

```bash
git clone https://github.com/956zs/ii-modules
cd ii-modules
cargo build --release --manifest-path tools/iimod/Cargo.toml
install -Dm755 tools/iimod/target/release/iimod ~/.local/bin/iimod
```

## Install your first module

Find a module you want from the [module listing](https://ii.n1cat.xyz/), open its card, and copy the install command — for example:

```bash
iimod install https://github.com/956zs/ii-modules/releases/latest/download/network_traffic-1.4.0.iimod
```

`iimod install` is **transactional**: if any step during installation fails (probe mismatch, hash mismatch, anchor failure, ...), it automatically rolls back, so the desktop never ends up in a half-broken state.

When installing from a URL, iimod automatically records the module's update source (origin), so `iimod update` can later track new versions — see [Daily Use & Updates](/en/guide/daily).

### Installing a local module directory

For development or manual downloads, you can also point at a module folder — running validation first is recommended:

```bash
iimod validate  my_module/   # validate manifest, layout, capability lint
iimod check     my_module/   # compatibility probes + dependencies + anchor dry run
iimod install   my_module/   # transactional install
```

### Tier B modules

Modules that modify stock files (marked **Tier B** in the listing) require explicit consent to install:

```bash
iimod install some_patch_module/ --allow-patches
```

::: warning
Every **update** to a Tier B module also requires re-passing `--allow-patches` — the patch content in the new version may differ.
:::

## Enabling and disabling modules

Once installed, ii's settings app (<kbd>Ctrl</kbd>+<kbd>Super</kbd>+<kbd>,</kbd>) gains a **Modules** page: toggle modules on/off and adjust each module's own settings.

You can also use the CLI:

```bash
iimod list              # list installed modules and their status
iimod enable  <id>
iimod disable <id>
```

## After a dots-hyprland update {#reapply}

A dots-hyprland update runs `rsync --delete` across the entire shell tree, wiping out installed modules along with it. **You must run this after every update**:

```bash
iimod reapply
```

Full state lives in `~/.local/share/iimp/` (outside rsync's cleanup scope); `reapply` reapplies every module and patch in one shot.
