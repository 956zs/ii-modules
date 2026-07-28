---
description: Starting from scratch — install the iimod CLI, then install your first IIMP module.
---

# Install & Quick Start

This page walks you through it from scratch: get the `iimod` CLI installed, then install your first module.

## Prerequisites

- The **illogical-impulse** Quickshell desktop from [dots-hyprland](https://github.com/end-4/dots-hyprland) already installed
- Linux x86_64 (for other architectures, see [Building from Source](#building-from-source))

## Install the iimod CLI

Use the first-party installer served by this site to download the official binary from the stable endpoint and verify its SHA256:

```bash
sh -c 'script=$(curl --fail --location --proto "=https" --tlsv1.2 --silent --show-error https://ii.n1cat.xyz/install-iimod.sh) && [ -n "$script" ] && sh -c "$script"'
```

Before prompting, the script explains what it installs, the `/usr/local/bin/iimod` destination, SHA256 verification, and when `sudo` may request your password. It downloads the binary only into a restricted temporary directory. An invalid or mismatched checksum stops the installation before `sudo`, and temporary files are always removed.

This one-line command first retrieves the complete, nonempty installer over HTTPS. It executes the script only after `curl` succeeds, including its HTTP error check, so failed or truncated transfers are never executed. The trust boundary still includes `ii.n1cat.xyz`, TLS, and the complete script served by the site at that time. To review it first, open [install-iimod.sh](https://ii.n1cat.xyz/install-iimod.sh), or download it locally and inspect it before running it. The binary itself is never piped into `sudo`: the script verifies SHA256 first, then invokes `sudo install` separately.

::: tip Stable endpoint
The site projects the binary and `.sha256` from the highest-versioned `iimod/v<version>` release. The CLI and every module release independently; neither depends on the repository-wide Latest Release.
:::

### Building from Source

```bash
git clone https://github.com/956zs/ii-modules
cd ii-modules
cargo build --release --manifest-path tools/iimod/Cargo.toml
install -Dm755 tools/iimod/target/release/iimod ~/.local/bin/iimod
```

## Install your first module

The install command uses the immutable GitHub Release asset URL selected by the site's aggregate index, for example:

```bash
iimod install https://github.com/956zs/ii-modules/releases/download/module%2Fnetwork_traffic%2Fv1.5.0/network_traffic-1.5.0.iimod
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
