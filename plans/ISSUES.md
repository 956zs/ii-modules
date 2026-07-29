# Issues

## Module i18n consistency

- ✅ P1 resolved: Registry v2 `translationKeys` now records contributor references, with store-backed reconciliation across install, uninstall, upgrade, and reapply. Same-value sharers survive either uninstall order until the last contributor; pre-migration exclusive records are repaired; user edits are preserved; different-value winners and survivor promotion are deterministic.
- ✅ P2 resolved: `animation_tuner` now has complete canonical `zh_TW` and `zh_CN` catalogs plus exact `i18n.sources.json` declarations for both controlled dynamic expressions. Manifest patch content and dynamic source sets are scanned before orphan decisions.
- ✅ P2 resolved: Repository-level `iimod i18n extract/check` now validates payload directories and packages, and CI/release enforce exact `zh_TW` + `zh_CN` first-party catalogs with no orphans. Portable validation keeps runtime English-source fallback and requires complete canonical `zh_TW` without changing protocolVersion 1 compatibility.
- ✅ P1 Codex review resolved: Scanner false negatives in template interpolations and immediate `.arg(...)` arguments, plus regex misclassification after `return`/`throw`/`case`, now have direct red/green CLI regressions. Restored the affected `memory_center`, `battery_trend`, and `screentime` catalog keys.
- ✅ P1 Codex review resolved: Live and immutable-store dictionaries fail closed before mutation on malformed, unreadable, or missing managed data; these paths return integrity exit 6 and retain registry/store/live state. Legacy doctor registry rebuild remains compatible with valid protocol-v1 payloads that predate translation catalogs.
- ✅ P1 Codex review resolved: Uninstall now journals and rolls back stock, host, projections, translations, live payloads, and store payloads. A deterministic mid-transaction translation-write failure verifies full restoration.
- ✅ P1 Codex review resolved: `reapply` now snapshots durable host state before preflight and journals stock/pristine, live/store payloads, host projections, dictionaries, registry, index, and config before mutation. Deterministic later-locale, empty-registry host-projection, and post-preflight registry failures restore the complete pre-transaction state.
- ✅ P1 Codex review resolved: Installing a contributor whose translation equals an existing unmanaged user entry no longer claims ownership or deletes that entry on uninstall. References are created only for newly projected keys, prior managed evidence, or schema-v1 legacy repair.
- ✅ P2 Codex review resolved: Scanner regex recognition now covers whole-word, non-member `typeof`, `void`, and `delete` prefix expressions without regressing chained division parsing.

## Concurrent iimod transactions

- ✅ Host downgrade/freshness protection fixed in `iimod` 1.2.0: registry remains schema v2, while `$STATE/host/current.json` selects an immutable monotonic generation bundle containing both host assets and the full target-aware host patch set. New mutators atomically install a permanent exact `1\n` legacy lock fence before switching to stable-inode `flock` on `mutation.lock.v2`, so released old binaries fail before host writes; freshness-aware older binaries reuse a validated newer bundle, future protocols and generation collisions/corruption fail closed, and first migration compares full sentinel plus fence version/content identity.
- 🟡 P2 remains: `mutation.lock.v2` is still fail-fast instead of bounded/FIFO waiting, so independent development sessions cannot queue mutating transactions or show owner/progress. Continue assigning exactly one live mutation owner until waiting ships.
- 2026-07-29 recurrence evidence: plain `iimod install /tmp/network_traffic-1.6.0.iimod` resolved to the 2026-07-27 `~/.local/bin/iimod` (advertised version 1.1.0, SHA256 `5dba3b1a...`, stale embedded host). At 08:48:33 it rewrote the network_traffic payload, registry, and live 15,877-byte legacy `ModulesConfig.qml`; `verify` again reported intact. The worktree debug/release binaries also advertised 1.1.0 but embedded the 43,975-byte redesign, proving semver alone cannot identify host freshness. This exact released-lock/write sequence is now covered by `legacy_pid1_fence_blocks_released_host_downgrade`; tamper tests cover assets, sentinel, imports, fences, and immutable bundle integrity.

## Independent product release review

- ✅ Fixed: `.github/workflows/pages.yml` omitted `release.unpublished`, so unpublishing a Release would not withdraw it from Pages until another deployment.
- ✅ Fixed: `site/scripts/release-projection.mjs` accepted extra assets in a namespaced Release, allowing mixed-product Releases to bypass the one-product contract. Projection now requires exactly the product artifact and `SHA256SUMS`.
