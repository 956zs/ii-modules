# Issues

## Module i18n consistency

- ✅ P1 resolved: Registry v2 translation ownership now records contributor references, preserves same-value sharers and user edits, validates immutable store references, and makes uninstall rollback transactional.
- ✅ P1 Codex follow-up resolved: `reapply` now snapshots durable host state before preflight and journals stock/pristine, live/store payloads, host projections, dictionaries, registry, index, and config. Later-locale, empty-registry projection, and post-preflight registry failures restore the complete pre-transaction state.
- ✅ P1 Codex follow-up resolved: Installing a contributor whose value equals an existing unmanaged user translation no longer claims or later deletes that entry; references require a newly projected key, prior managed evidence, or schema-v1 legacy repair.
- ✅ P1 resolved: Scanner review regressions cover template interpolation, nested `.arg()` arguments, unrelated grouped postfix calls, expression-keyword regexes, control-flow statement regexes, regex character classes, and division expressions.
- ✅ P2 Codex follow-up resolved: Regex recognition now also covers whole-word non-member `typeof`, `void`, and `delete` prefix expressions without regressing control-flow or division contexts.
- ✅ P2 resolved: All first-party modules now pass exact canonical `zh_TW` and `zh_CN` checks with no orphans; CI and release source/package workflows enforce the same policy.

## Concurrent iimod transactions

- ✅ Host downgrade/freshness protection fixed in `iimod` 1.2.0: registry remains schema v2, while `$STATE/host/current.json` selects an immutable monotonic generation bundle containing both host assets and the full target-aware host patch set. New mutators atomically install a permanent exact `1\n` legacy lock fence before switching to stable-inode `flock` on `mutation.lock.v2`, so released old binaries fail before host writes; freshness-aware older binaries reuse a validated newer bundle, future protocols and generation collisions/corruption fail closed, and first migration compares full sentinel plus fence version/content identity.
- 🟡 P2 remains: `mutation.lock.v2` is still fail-fast instead of bounded/FIFO waiting, so independent development sessions cannot queue mutating transactions or show owner/progress. Continue assigning exactly one live mutation owner until waiting ships.
- 2026-07-29 recurrence evidence: plain `iimod install /tmp/network_traffic-1.6.0.iimod` resolved to the 2026-07-27 `~/.local/bin/iimod` (advertised version 1.1.0, SHA256 `5dba3b1a...`, stale embedded host). At 08:48:33 it rewrote the network_traffic payload, registry, and live 15,877-byte legacy `ModulesConfig.qml`; `verify` again reported intact. The worktree debug/release binaries also advertised 1.1.0 but embedded the 43,975-byte redesign, proving semver alone cannot identify host freshness. This exact released-lock/write sequence is now covered by `legacy_pid1_fence_blocks_released_host_downgrade`; tamper tests cover assets, sentinel, imports, fences, and immutable bundle integrity.

## Independent product release review

- ✅ Fixed: `.github/workflows/pages.yml` omitted `release.unpublished`, so unpublishing a Release would not withdraw it from Pages until another deployment.
- ✅ Fixed: `site/scripts/release-projection.mjs` accepted extra assets in a namespaced Release, allowing mixed-product Releases to bypass the one-product contract. Projection now requires exactly the product artifact and `SHA256SUMS`.

## ConfigLoader drift convergence (2026-08-24)

- 🟢 P3: `lib/ConfigLoader.template.qml` + `tools/lib-sync/check-configloader.mjs`
  now define and enforce skeleton invariants; the `animation_tuner`
  deviation is allowlisted with reasons in `tools/lib-sync/allowlist.json`.
  Converge it at its next release: add `blockWrites`/`atomicWrites` and a
  materializing (or writable-echo) guard, then remove the allowlist entry.
  `memory_center` converged in 1.2.1 (2026-10-16) and left the allowlist.
- ✅ P2 resolved (2026-10-16): `memory_center/ConfigLoader.qml` now carries
  the golden-master skeleton (`materializing` guard, `blockWrites`,
  `atomicWrites`, FileNotFound-only materialization). Live 1.2.1: an
  external `touch` of `modules/memory_center.json` triggers no write back.

## Module follow-ups from 2026-08-24 fix round

- 🟢 P3 battery_trend: live analytics showed implausible drain rates
  ("30 d: 40.5 %/h") — likely short discharge windows plus chunky sysfs
  percent drops inflating dis/disSec aggregates. Data semantics, separate
  from the fixed popup defect.
- 🟢 P3 network_traffic: pktz truncates comm names to 15 chars
  ("laptop-monitor-", "RvControlSvc.ex") — cosmetic naming in the per-app
  list, accounting unaffected.

## Adaptive bar follow-ups (2026-10-14)

- 🟢 P3 iimod host P5/P6 (vertical bar): bar-slot Loaders still reserve the
  implicit height of modules that hide their own root (same defect P3 had
  before host generation 3). Not live-verifiable without switching the user's
  bar to vertical; apply the Column equivalent of the P3 Row fix.
- 🟢 P3 iimod host P3: when at least one bar module is enabled but every one
  hides itself, the right-section RowLayout still adds one 5 px spacing (only
  an invisible layout child drops it, and hiding from item.visible latches).
- 🟡 P2 iimod upgrade semantics: `iimod install <newer>` of a Disabled module
  re-enables it (sandbox evidence with clock_popup_slim 2.1.0 -> 3.0.0). Use
  `--no-enable` until upgrades preserve the previous state.
- ✅ P3 memory_center store drift resolved (2026-10-16): 1.2.1 installed
  over the drifted 1.2.0 store without a conflicting-contributor warning;
  live zh_TW "Show percentage in the bar" is the repo value again.

## Bar pages follow-ups (2026-10-15)

- 🟢 P3 iimod host dev loop: a changed asset at the same HOST_GENERATION is a
  content collision (fails closed by design), so iterating on an unreleased
  generation requires hand-editing `~/.local/share/iimp/host/`. Consider a
  `doctor --drop-generation <n>` guarded to generations newer than the last
  released one.
- 🟢 P3 `ensure_host` writes host assets but never prunes files no longer in
  the bundle; a renamed asset leaves the old file in `$II/mod/iimp/`.
- 🟢 P3 bar pages reserve the widest page's width; a module that only grows
  on a secondary page also widens the main page. Acceptable for now; a
  per-page width with animated resize would need adaptive_bar to tolerate
  the churn.
- 🟢 P3 adaptive_bar could page modules automatically when the right section
  overflows (would write `barPagesJson`, churning config.json); deferred,
  explicit pages only for now.

## Idle inhibitor after shell restart (2026-10-23)

- ✅ Fixed in `idle_modes` 1.0.1: after a full shell restart, "full" (stock
  inhibit restored as true) left hypridle free to lock and suspend. Hyprland
  0.56.2 checks an inhibitor's surface visibility only on inhibitor
  create/destroy and focus/window/fullscreen events, not on layer-surface map;
  Quickshell's `IdleInhibitor` sends `create_inhibitor` before its 0x0 surface
  maps. Hot reloads reuse the mapped window and were never affected.
- 🟢 P3 upstream: the same race affects stock ii without `idle_modes` whenever
  a shell restart restores `Persistent.states.idle.inhibit`. Candidate reports:
  Hyprland (recheck inhibitors on layer map) or Quickshell (create the
  inhibitor after the first configure/commit). Not filed; needs owner OK.
- 🟡 P2 external: a full `qs -c ii` restart stalled ~50 s before `Persistent`
  and IIMP window modules loaded. Root cause (gdb): the stock `Weather`
  singleton's `PositionSource` (`bar.weather.enableGPS`, true even with
  weather disabled) makes a synchronous D-Bus call to GeoClue2 on the main
  thread, and `geoclue.service` never starts since GLib 2.90.1 (upgraded
  2026-10-22): GLib issue #4078, a GIO lock-order deadlock between
  `_g_io_module_get_default` (proxy resolver, on the new netlink
  `can_reach_async` thread) and `g_vfs_get_default`. Reproduced as a user
  process; `GIO_USE_PROXY_RESOLVER=dummy` in a geoclue drop-in avoids it
  (3/3 vs 3/3 hangs). Not a module bug; drop the workaround once GLib ships
  a fix.
- 🟢 P3 iimod gotcha: `install --reinstall` and `reapply` re-snapshot the
  current live stock regions into `$STATE/pristine` and new backups, so
  out-of-band debug edits to stock files survive recomposition. Strip them
  from live, pristine and backups by hand, then confirm with a pristine diff.
