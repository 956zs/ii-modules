# Issues

## Concurrent iimod transactions

- ✅ Host downgrade/freshness protection fixed in `iimod` 1.2.0: registry remains schema v2, while `$STATE/host/current.json` selects an immutable monotonic generation bundle containing both host assets and the full target-aware host patch set. New mutators atomically install a permanent exact `1\n` legacy lock fence before switching to stable-inode `flock` on `mutation.lock.v2`, so released old binaries fail before host writes; freshness-aware older binaries reuse a validated newer bundle, future protocols and generation collisions/corruption fail closed, and first migration compares full sentinel plus fence version/content identity.
- 🟡 P2 remains: `mutation.lock.v2` is still fail-fast instead of bounded/FIFO waiting, so independent development sessions cannot queue mutating transactions or show owner/progress. Continue assigning exactly one live mutation owner until waiting ships.
- 2026-07-29 recurrence evidence: plain `iimod install /tmp/network_traffic-1.6.0.iimod` resolved to the 2026-07-27 `~/.local/bin/iimod` (advertised version 1.1.0, SHA256 `5dba3b1a...`, stale embedded host). At 08:48:33 it rewrote the network_traffic payload, registry, and live 15,877-byte legacy `ModulesConfig.qml`; `verify` again reported intact. The worktree debug/release binaries also advertised 1.1.0 but embedded the 43,975-byte redesign, proving semver alone cannot identify host freshness. This exact released-lock/write sequence is now covered by `legacy_pid1_fence_blocks_released_host_downgrade`; tamper tests cover assets, sentinel, imports, fences, and immutable bundle integrity.

## Independent product release review

- ✅ Fixed: `.github/workflows/pages.yml` omitted `release.unpublished`, so unpublishing a Release would not withdraw it from Pages until another deployment.
- ✅ Fixed: `site/scripts/release-projection.mjs` accepted extra assets in a namespaced Release, allowing mixed-product Releases to bypass the one-product contract. Projection now requires exactly the product artifact and `SHA256SUMS`.
