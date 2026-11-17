# Batch 2 group E (ii-modules): N39 idle gate, N38 capsule

Branch `feat/androlink-keep-awake` from `feat/androlink-modules` (0a1215f), not
pushed, nothing installed live. Contracts: androlink
`plans/features-2026-11-17.md` §Contracts (status.json `keep_awake` and
`calls_back`, `androlink --refresh`, idle gate).

## What changed

| Module | Files | Change |
|---|---|---|
| `idle_modes` 1.0.1 → 1.1.0 | `idle-mode-gate.sh`, `ConfigLoader.qml`, `module.json` | In mode off, the gate skips the idle suspend while androlink's status file is fresh and `keep_awake` lists reasons, on AC or with the battery at or above the floor |
| | `tests/idle-modes.test.mjs` | Gate decision tests in sandboxes |
| | `README.md`, `README.en.md` | Decision table, options, rules, limits |
| `androlink_status` 1.0.0 → 1.1.0 | `StatusLogic.js`, `CommandRunner.qml` | `calls_back` → `callsBack`, `savingBattery` in the bar model, `--refresh` as a global action, exit codes per action kind, `refreshWaitSecs` |
| | `bar.qml`, `PhonePanel.qml`, `ConfigLoader.qml`, `module.json`, `translations/*` | 「省電中」 label in the capsule, panel status line and Connection row; 「重新連線」 action with a cool-down; `refreshMinIntervalSecs` option |
| | `tests/status.test.mjs`, `tests/fixtures/saving-battery.json` | Parsing, bar model, argv, exit codes, cool-down |
| | `README.md` | Requirements, behaviour, options, limits |

## Decisions

- Option names follow the module convention (camelCase JsonAdapter
  properties): the contract's `keep_awake_battery_floor` is
  `keepAwakeBatteryFloor` (20, 0–100). The 90 s freshness is also an option,
  `keepAwakeMaxAgeSecs` (90, 15–3600). The ConfigLoader clamps both; the
  script clamps the same ranges itself (it can run before the shell, or after
  a hand edit). A test keeps the two range sets equal.
- Freshness mirrors androlink's own rule: stale when older than the limit or
  more than a third of it (one heartbeat) in the future.
- Status file: only with an absolute `XDG_RUNTIME_DIR`, at most 64 KiB,
  exactly one JSON value (`jq -s`), `version` 1, `running` true, numeric
  `updated` in (0, 1e11). A missing or `null` `keep_awake` is none; any other
  non-array is invalid. Anything else falls back to the plain mode check.
- Reason codes: any code-shaped string counts (forward compatible with new
  reasons), filtered by `\A[a-z][a-z0-9_]{0,31}\z`, unique, sorted, at most 8,
  so the log line never carries file text. (`^…$` in jq lets a trailing
  newline through; checked.)
- Power: any `Mains` supply with `online` 1 is AC; the level is the mean
  `capacity` of system batteries; `scope` `Device` (mice, headsets) and `USB`
  supplies are ignored; type-less entries are named `AC*`/`ADP*`/`ACAD*` or
  `BAT*`. No battery at all counts as mains (desktop). A battery whose level
  can't be read never holds the suspend. `IDLE_MODES_POWER_SUPPLY_DIR`
  overrides `/sys/class/power_supply` for tests only.
- Log: one line per run, e.g. `idle-mode-gate: mode off, androlink keep_awake
  mic,transfer, on AC, not suspending`; `half`/`full` lines are unchanged.
- Capsule: horizontal bar shows "Saving battery" (dim) beside the phone; the
  state needs a current file, a disconnected primary phone and
  `calls_back: true`. Panel: status line and Connection row (icon
  `battery_saver`) say it.
- Reconnect: shown whenever a phone is listed (it refreshes every phone),
  enabled while the file is current, the runner is idle and the cool-down is
  over. Fixed argv `["androlink", "--refresh"]`, never a phone argument.
  Cool-down `refreshMinIntervalSecs` (10, 0–300, same as androlink's
  `connection.refresh_min_interval_s`), per panel. Exit 0 shows
  「正在重新連線。」; exit 2 from a global action shows "That didn't work
  (code 2)" instead of phone-not-found (an androlink without the option).
- Catalog strings were written by the feature owner in this run (no
  independent i18n subagent was available): 「省電中」 matches androlink's own
  `link.calls_back`, 「重新連線」 matches `indicator_tools`.

## Tests

| Check | Result |
|---|---|
| `node --test modules/*/tests/*.test.mjs` | 247/247 (was 228: +14 idle_modes, +5 androlink_status) |
| Offscreen harness | 80/80 (was 67: +13 N38 checks) |
| `iimod validate` / `check` (both modules) | ok |
| `iimod i18n check --all --deny-orphans`, per-module exact check, extract | ok, 14 modules |
| `node tools/lib-sync/check-configloader.mjs` | 11 copies, 0 undeclared deviations |
| `tools/release/test-contracts.sh` / `test-publish.sh` | 15 / 13 passed |
| `qmlformat` parse of changed QML, `bash -n` gate, `git diff --check` | ok |

Gate tests run the script with a temporary HOME/XDG tree, a fake power
supply tree and fake `systemctl`/`loginctl` first in PATH. They cover half
and full, fresh/stale/future/missing/invalid/stopped files, a relative
`XDG_RUNTIME_DIR`, empty/missing/null/junk `keep_awake`, code filtering, AC,
no battery, battery above/at/below the floor, option clamping, peripheral,
USB, several, unreadable and type-less supplies, the systemctl→loginctl
fallback and usage errors.

The harness is a separate copy, `~/.cache/ii-modules-scratch-b2ii` (the
original `~/.cache/ii-modules-scratch` is untouched). Its sandbox is a
read-only copy of the live shell tree with the branch payload laid over the
installed `androlink_status` (no iimod run). New checks: saving-battery
model and capsule label, panel status line, Reconnect visible/enabled, argv
`[--refresh]`, "Reconnecting." message, cool-down on and off, no second run
inside the interval, exit 2 and 1 messages, several phones still unnamed,
stale file disables Reconnect, `battery_saver`/`sync` glyphs. Snapshots
`bar-saving.png` and `panel-saving.png` were checked by eye.

Not run: the iimod Rust suite (no Rust changed).

## Open

- Owner install: `iimod install modules/androlink_status`,
  `iimod install modules/idle_modes --allow-patches`, and copy the gate
  script again (`install -Dm755 … ~/.config/hypr/custom/scripts/idle-mode-gate.sh`);
  the installed script is a copy and does not update with the module.
- `site/public/registry.json` is already stale on the base branch (no
  androlink_status, inline_reply, aula_keys); regenerate when publishing.
- hypridle runs the suspend command once per idle period: when a call ends
  while the PC stays idle, it suspends only after input and a new idle period.
- androlink drops a rate-limited `--refresh` quietly (exit 0), so the panel
  still shows 「正在重新連線。」 then.
- The panel does not show `mic` or the top-level `keep_awake` (out of scope).
