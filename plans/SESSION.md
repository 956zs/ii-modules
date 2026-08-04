# Session

## indicator_tools applet menus

- ✅ Task 9: Fixed Bluetooth Material menu empty labels, grouping, and device/profile pairing.
- ✅ Task 10: Implemented Wi-Fi Material renderer from nm-applet QsMenuHandle.
- ✅ Task 11: Integrated both renderers, bridge, manifest, README, and translations.
- ✅ Task 12: `iimod validate` and `iimod check` pass for v3.4.0; installed runtime matches repo; latest live log has no indicator errors.
- 🔄 Task 13: Codex review running.
- ⏳ Task 14: Handle verified Codex feedback.
- ✅ Task 15: Diagnosed and fixed opening animation jank without removing/simplifying animations.

## indicator_tools decisions and evidence

- Blueman and nm-applet D-Bus menus remain the sole action/state owners.
- Both stock indicators retain left-click behavior; right-click opens module-styled menus.
- Root cause of animation jank was synchronous Popup/QsMenuOpener/delegate creation plus model-driven top-level geometry changes during the existing animations; D-Bus latency itself was only ~7–10 ms.
- Quickshell 0.2.1 `LazyLoader.activeAsync` now incubates renderers off the click path.
- Popup anchoring uses a window-relative `itemRect` snapshot rather than retaining `anchor.item` across hot reload.
- Menu/layout height settles before the original opacity and elementResize animations start; animation durations/easing were not reduced or removed.
- User confirmed the result is much smoother.

## website documentation automation

- ✅ Task 8: Build-time module catalog, dynamic bilingual VitePress docs/navigation, and Pages rebuild-on-module-change shipped through PR #1.

## independent product releases

- ✅ Task 1: Created `feat/independent-releases` from `main` after PR #2 merged.
- ✅ Task 2: Split mixed release tooling into module-only and CLI-only builders/verifiers.
- 🔄 Task 3: Build a fail-closed Pages projection from namespaced GitHub Releases.
- ⏳ Task 4: Split GitHub Actions and connect release changes to Pages deployment.
- ⏳ Task 5: Update release documentation and migration notes.
- ⏳ Task 6: Run full verification, including product dry-runs and site build.
- ⏳ Task 7: Codex review.
- ⏳ Task 8: Handle verified Codex feedback.

### Task 2 interfaces and evidence

- Module build: `tools/release/build-module.sh [--allow-dirty] modules/<id> [module/<id>/v<semver>]`.
- Module verify: `tools/release/verify-module.sh RELEASE_DIR [module/<id>/v<semver>]`.
- CLI build: `tools/release/build-cli.sh [--allow-dirty] [iimod/v<semver>]`.
- CLI verify: `tools/release/verify-cli.sh RELEASE_DIR [iimod/v<semver>]`.
- Compatibility entry points `tools/release/build.sh` and `tools/release/verify.sh` dispatch only namespaced module or CLI tags; generic `v*` tags are rejected.
- Each output contains exactly one product artifact plus `SHA256SUMS` and `RELEASE_NOTES.md`; release notes are excluded from checksums. New flows emit no starter zip or `index.json`.
- Module packages embed canonical origin `https://ii.n1cat.xyz/index.json`; builder and verifier validate the manifest/tag contract and run `iimod validate` plus fixture-backed `iimod check` on the package.
- CLI builder validates Cargo/tag versions and runs fmt, clippy, 46 unit tests, 13 integration tests, and release build; verifier checks checksum, executable mode, and `iimod --version`.
- Contract verification: `tools/release/test-contracts.sh` (13 cases).
- Dry-runs verified with `RELEASE_DIST_DIR=/tmp/ii-release-task2-module tools/release/build.sh --allow-dirty module/network_traffic/v1.5.0` and `RELEASE_DIST_DIR=/tmp/ii-release-task2-cli tools/release/build.sh --allow-dirty iimod/v1.1.0`, followed by the matching `tools/release/verify.sh` commands.

### Decisions

- Module tags are `module/<id>/v<semver>`; CLI tags are `iimod/v<semver>`.
- Every GitHub Release contains artifacts for exactly one independently versioned product and is created with `--latest=false`.
- The canonical module origin is `https://ii.n1cat.xyz/index.json`, retaining the exact `indexVersion: 1` schema accepted by `iimod update`.
- Pages selects the highest semver per namespaced product, requires the exact expected asset, downloads it, and recomputes SHA256 before publishing the aggregate index.
- CLI stable endpoints are `https://ii.n1cat.xyz/downloads/iimod/linux-x86_64` and `.sha256`.
- Legacy `v1.4.0` remains the repository-wide generic Latest compatibility bridge; no future product artifacts are added to it.
- No GitHub Releases will be published as part of implementation or verification without separate user approval.
