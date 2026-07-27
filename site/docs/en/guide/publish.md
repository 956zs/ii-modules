---
description: Package a .iimod, host an update source, and list your module on the IIMP module directory.
---

# Publish & List

Once your module is written and both `validate`/`check` pass, the next step is letting other people install it — and update it.

## Packaging a `.iimod`

```bash
iimod pack my_widget/ --origin https://example.com/mods/index.json
```

This produces `my_widget-0.1.0.iimod` (a zip file containing `integrity.json`: the manifest and a sha256 for every file).

::: warning pack requires an origin
`iimod pack` must be passed `--origin <index.json URL>` (embedding the update source, so anyone with the file can install it and then update it), or explicitly passed `--no-origin` to opt out (local/development use only). Passing neither flag causes packing to be rejected outright.
:::

## Hosting an update source (index.json)

The source is just a static JSON file hosted at any HTTPS location — GitHub Releases, GitHub raw, or a self-hosted server all work:

```json
{
  "indexVersion": 1,
  "modules": {
    "my_widget": {
      "version": "0.1.0",
      "url": "my_widget-0.1.0.iimod",
      "sha256": "…"
    }
  }
}
```

- `url` can be relative to the index.json's location
- `sha256` is required — the download side always verifies it, rejecting the install on mismatch
- Shipping a new version = upload the new `.iimod` + update `version`/`url`/`sha256` in index.json

Users don't have to do anything on their end — `iimod update` will naturally see the new version.

## Listing on the module directory (ii.n1cat.xyz)

For modules hosted in this repository, the landing catalog, localized metadata, Tier, capabilities, module docs, and VitePress navigation are all derived from `modules/<id>/module.json` and `README.md`. Submit the complete `modules/my_widget/` directory in a PR; do not edit `site/public/registry.json` by hand.

Minimum requirements:

- The directory name must equal the manifest `id`
- `name` and `description` must include both `zh_TW` and `en_US`
- `README.md` is required; `README.en.md` is optional, and its absence is stated explicitly before the Traditional Chinese fallback
- Tier B is derived from non-empty `patches`; `capabilities` and `requires` come directly from the manifest
- From `site/`, run `npm run catalog:generate` and then `npm run build`; stale generated catalog data fails the build

After merge, the landing catalog, both module documentation routes, and documentation navigation update together. A download is only enabled once the release index contains the same module version.

## Hosting via GitHub Releases (recommended)

Every product in this repository releases independently: modules use `module/<id>/v<version>` tags, while the CLI uses `iimod/v<version>` tags. Each GitHub Release contains only that product's artifact, `SHA256SUMS`, and release notes, and does not replace the repository-wide Latest release.

Before releasing a module, its manifest `id` and `version` must exactly match the tag:

```bash
git tag module/my_widget/v0.1.0
git push origin module/my_widget/v0.1.0
```

The workflow embeds `https://ii.n1cat.xyz/index.json` as the package origin. Pages rescans every namespaced release, validates exact asset names, recomputes SHA256, and projects the highest semver for each module into a compatible aggregate `indexVersion: 1` index.

Merging `modules/<id>` source only updates the catalog. The website enables downloads only after the matching namespaced release succeeds. The CLI releases separately through `iimod/v<version>` and never shares a version number or Release with a module.
