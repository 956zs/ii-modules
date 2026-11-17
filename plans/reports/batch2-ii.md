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

## Security fixes

Fixes for the batch 2 security review findings on `idle_modes`, on the same
branch (`73a5d2f`, `72b6015`, `ff7848f`), not pushed, nothing installed
live. `idle_modes` 1.1.0 → 1.2.0 (two new options and the `resume`
command).

| Finding | Commit | What changed |
|---|---|---|
| II-GATE-1 / F1 (confirmed, low) | `ff7848f` | The gate waits while it holds the idle suspend, checks again every `keepAwakeRecheckSecs` and suspends once the hold no longer applies or after `keepAwakeMaxHoldMins`; input, a mode change or a screen on ends the wait |
| II-GATE-2 (info) | `73a5d2f` | An unreadable power supply class, or an offline `Mains` supply with no battery visible, is unknown and lets the suspend run |
| II-GATE-3 (info) | `72b6015` | A top-level `heartbeat_s` (1–3600) widens the freshness limit to three heartbeats |

II-GATE-1 / F1 in detail:

- Re-check: every `keepAwakeRecheckSecs` (60, 15–600) the gate reads the
  mode, floor, freshness option, status file and power again. It suspends when
  `keep_awake` is empty, the file is stale, stopped, missing or invalid, or
  the battery is below the floor or unreadable.
- Limit: `keepAwakeMaxHoldMins` (120, 1–1440); at the limit it suspends
  whatever androlink reports. The ConfigLoader clamps both options.
- Ends without a suspend: `idle-mode-gate.sh resume` (hypridle
  `on-resume`), the mode leaving off, or a screen on again / no answer from
  `hyprctl`.
- Hold file: `$XDG_RUNTIME_DIR/idle-mode-gate.pid` (0600, `flock`), only in a
  private user-owned runtime dir; a symlink or foreign file stops the wait.
  `resume` signals only the lock holder whose `/proc` cmdline is the gate's
  `suspend` and removes unlocked leftovers. A new idle period replaces a gate
  that still waits.

Tests per finding:

- II-GATE-1 / F1, Node: re-checks that suspend (keep_awake cleared, battery
  drop, floor raised, level unreadable, stale/stopped/missing/invalid file);
  waits that end without a suspend (half, full, one screen on, no screens,
  junk or failing `hyprctl`, hold file removed or naming another PID); the
  limit (15 s × 4, 45 s × 2); option rounding, clamping and junk; runtime dir
  0777/0770/0757; symlink and directory hold files; `resume` stopping a real
  waiting gate at once with no sleep left behind; a second idle period
  replacing the first; `resume` never signalling an unrelated PID or a
  non-gate lock holder; the README `sed` on a sample `hypridle.conf`
  (idempotent).
- II-GATE-1 / F1, harness: the ConfigLoader heals and writes back the options;
  the real gate with real `sleep` and `flock` keeps a 0600 hold file, reads
  the healed options, stops on `resume` in about 110 ms, suspends at the 15 s
  check once `keep_awake` clears, and ends the wait when a screen is on.
- II-GATE-2: missing dir, a regular file, mode 000 and 644 dirs, offline
  `Mains` alone and with a peripheral battery, `Mains` without `online`,
  online `Mains` without a battery; an empty dir is still a desktop.
- II-GATE-3: 120 s and 3600 s heartbeats old and ahead, 10 s and 1 s
  heartbeats keep 90 s, 31.5 s, ten invalid values (0, 0.5, -30, 3601, 1e9,
  string, null, bool, array, object), a 300 s option over three 30 s
  heartbeats.

Decisions:

- The loop sits in the gate, as the fix plan asks, with the three conditions
  the F1 verifier set for a loop: cancel on input, one waiting copy (`flock`),
  and a hard maximum (`keepAwakeMaxHoldMins`). `hypridle.conf` is outside the
  shell tree and iimod patches only shell QML, so the module can't add the
  `on-resume` line; the READMEs give the one-line edit and an idempotent
  `sed`. Without that line the loop stays safe: it suspends from a check only
  while every screen is still DPMS-off (`hyprctl monitors`), which the stock
  10-minute screen-off listener guarantees until input, and stops on any
  other answer.
- At the limit the gate suspends on AC too (the F1 verifier suggested battery
  only). This also bounds a stalled `transfer` reason (AL-KEEPAWAKE-1, F2)
  from the gate's side; the owner can raise the limit to 24 h.
- Freshness uses the longer of the option and three heartbeats, so the option
  stays a floor; with the defaults both give 90 s.
- The optional DMI `chassis_type` check from the II-GATE-2 verifier was not
  added (P3 in `plans/ISSUES.md`).
- The earlier Open item "hypridle runs the suspend command once per idle
  period" is resolved by II-GATE-1.

Checks:

| Check | Result |
|---|---|
| `node --test modules/*/tests/*.test.mjs` | 263/263 (was 247: +16 idle_modes) |
| Offscreen harness (`~/.cache/ii-modules-scratch-b2ii`) | 89/89 (was 80: +9 idle_modes) |
| Mutation checks on the gate (8: TERM trap, `-x`, offline Mains, heartbeat, screens, cmdline check, hold-file token, private runtime dir) | each caught by a test |
| `iimod validate` / `check` (idle_modes 1.2.0) | ok |
| `iimod i18n check --all --deny-orphans`, idle_modes extract/check | ok, 14 modules |
| `node tools/lib-sync/check-configloader.mjs` | 11 copies, 0 undeclared deviations |
| `tools/release/test-contracts.sh` / `test-publish.sh` | 15 / 13 passed |
| `bash -n` gate, `qmlformat` ConfigLoader, `git diff --check` | ok |

The harness gate checks run with fake `hyprctl`/`systemctl`/`loginctl`
first on the gate's own PATH only, and are skipped (as a failure) unless
`command -v` resolves all three to the fakes.

Open:

- Owner install: `iimod install modules/idle_modes --allow-patches` (1.2.0),
  copy the gate again, add the `on-resume` line with the README `sed`, then
  restart hypridle through Hyprland.
- androlink `plans/features-2026-11-17.md` (N39 row, §Idle gate) should
  mention the re-check, the limit and `heartbeat_s`; that file is outside
  this repo.
- The gate reads `heartbeat_s` only if androlink writes it at the top level
  of `status.json`; until then the option applies.

## Security fixes, round 2

Fixes for the batch 2 re-review findings on `idle_modes`, on the same branch
(`8e47d9c`, `f8c5892`, `52ab686`, `14bcbb8`). Nothing was pushed or
installed live. `idle_modes` goes from 1.2.0 to 1.2.1, a patch bump as the
round asked, although it adds the option `keepAwakeReleaseGraceSecs`.

| Finding | Commit | What changed |
|---|---|---|
| N-GATE-1 (confirmed, low) | `52ab686` | When `keep_awake` empties during a hold, the gate waits out a release grace (`keepAwakeReleaseGraceSecs`, 45, 15–600). It suspends only if the list was empty at every check through the grace; any reason that comes back keeps the hold |
| N-GATE-2 (confirmed, low) | `14bcbb8` | If the PC slept during a wait, the gate exits without a suspend. It detects this through a changed suspend count, or a boot clock more than 15 s past the wait |
| N-GATE-3 (info) | `f8c5892` | Each wait lasts at most until the hold limit (and the grace end), so a hold ends at `keepAwakeMaxHoldMins` and not one interval later |
| N-GATE-4 (info) | `8e47d9c` | The wait's `sleep` runs with the locked hold-file fd closed (`{fd}>&-`), so a SIGKILLed gate leaves no lock behind |

N-GATE-1 in detail:

- Only an empty `keep_awake` in a fresh, running status file gets the grace,
  and only while the power source would let a reason hold (AC, no battery,
  or a battery at or above the floor). `decide` sets `empty` in exactly that
  case.
- These suspend at once, with no grace: a stale, stopped, missing or invalid
  file; a battery below the floor or unreadable; the hold limit. The limit
  also cuts a grace short.
- During the grace the gate keeps checking at the normal interval, and the
  last wait is cut to end with the grace. With a 15 s interval and the
  default 45 s grace, the list has to be empty at four checks 15 s apart.
- The suspend line reads `androlink keep_awake none for 45 s, suspending`.
  When the battery is the reason, the line says so, e.g. `androlink
  keep_awake none, battery 19% below floor 20%`.
- The first decision of an idle period, when hypridle's listener fires, has
  no grace. An idle PC with nothing to hold still suspends at once, as
  before.

N-GATE-2 in detail:

- Before each wait, `mark_clock` reads three values:
  - `/proc/uptime`, which is CLOCK_BOOTTIME and keeps running through
    suspend and hibernation;
  - the wall clock;
  - `/sys/power/suspend_stats/success`, which is 0444 here.
- After the wait, `pc_slept` sees a sleep when the suspend count changed, or
  when the boot clock moved more than `slept_margin` (15 s) past the wait
  actually asked.
- If `/proc/uptime` can't be read, the wall clock is used instead. A forward
  step of the wall clock then only ends the wait. An unreadable count is
  ignored.
- The gate then prints `the PC slept during the wait, not suspending` and
  exits 0, and the EXIT trap removes the hold file.
- `IDLE_MODES_UPTIME_FILE` and `IDLE_MODES_SUSPEND_COUNT_FILE` override the
  two kernel files, for tests only.

Tests per finding (Node, `modules/idle_modes/tests/idle-modes.test.mjs`, 32 → 47):

- N-GATE-1:
  - empty for one check, then back: no suspend (60, 45, 60);
  - back during the grace, then empty again: the grace starts anew;
  - grace longer than the interval: empty at all four 15 s checks; a reason
    back at the third check: no suspend;
  - a grace the interval does not divide (100 s: 60 + 40);
  - stale, stopped, missing or invalid file during the grace;
  - battery below the floor or unreadable as the list empties (at once) and
    during the grace;
  - battery exactly at the floor still gets the grace;
  - the limit cuts a grace short;
  - no grace at the first decision, and its low-battery log line;
  - option values 15, 1, -30, 29.6, 600, 5000, a string, null and a bool.
- N-GATE-2:
  - the boot clock 16 s past the wait, and hours past it;
  - a counted suspend while the clock barely moved, and with `/proc/uptime`
    unreadable;
  - the 75 s boundary, and a clock that went back;
  - the margin measured from a wait the limit cut to 60 s (74 s holds,
    76 s is a sleep);
  - junk, empty or vanishing clock files never count as a sleep;
  - a sleep during the grace;
  - the default kernel paths.
- N-GATE-3:
  - 45 s → 45 + 15 and 600 s → 60 with a 1 min limit;
  - ten interval and limit pairs, where the waits sum to the limit and only
    the last one is shorter.
- N-GATE-4:
  - a real waiting gate is SIGKILLed;
  - the gate held the file open and its sleep did not;
  - the lock is free at once while the sleep still runs;
  - the next gate takes the lock and stops on `resume`.

Harness checks (`~/.cache/ii-modules-scratch-b2ii`, 89 → 95; these use real
`sleep`, `flock` and clocks):

- The ConfigLoader clamps and writes back the grace (1 → 15).
- With `keep_awake` emptied, the gate suspends after 30 s:
  `none for 15 s`.
- An empty list at one check, back before the grace check, followed by
  `resume`: no suspend. The checks are tracked by the gate's sleep PIDs,
  not by fixed delays.
- A fake `/proc/uptime` jumping 3600 s during a real 15 s wait, with
  androlink stopped: `the PC slept`, no suspend.
- The real clocks saw no sleep in the other real waits.
- After SIGKILL: the gate had one fd on the hold file and its sleep had
  none; the lock was free while the sleep lived on, and the next gate waited
  and stopped on `resume`.

Mutation checks: each of the following edits made at least one test fail.

- N-GATE-1: no grace, no reset when a reason comes back, no power condition,
  no cut at the grace end.
- N-GATE-2: never slept, no suspend count, margin from the interval instead
  of the wait, `>=` margin.
- N-GATE-3: no cut at the limit.
- N-GATE-4: no fd close.

Decisions:

- The grace is a module option with a floor of 15 s, androlink's
  `LINK_GRACE_MS`, so it can't be configured away. Its default of 45 s
  covers the 15 s link grace plus the restart, and is three checks at the
  minimum interval.
- The fix is on the gate side only. Keeping `mic`/`webcam` in `keep_awake`
  while androlink is reconnecting, the alternative the verdict mentions,
  is androlink code and outside this group's paths.
- Sleep detection uses the BOOTTIME margin plus the kernel's suspend count.
  The count also catches a lid close and open shorter than the margin. A
  logind `PrepareForSleep` listener would need a D-Bus client in a bash
  script, so it was not used.
- The window between the end of a wait and the checks after it (under a
  second, plus up to 5 s for `hyprctl`) is not covered: a suspend that
  starts and ends inside it is not seen.
- No Rust was touched in this group, so `cargo fmt`, `clippy` and
  `cargo test` do not apply. The iimod suite was not run.

Checks:

| Check | Result |
|---|---|
| `node --test modules/*/tests/*.test.mjs` | 278/278 (was 263: +15 idle_modes) |
| Offscreen harness (`~/.cache/ii-modules-scratch-b2ii`) | 95/95 (was 89: +6); sandbox and run dirs removed |
| Mutation checks (12, listed above) | each caught |
| `iimod validate` / `check` (idle_modes 1.2.1) | ok |
| `iimod i18n check --all --deny-orphans`, idle_modes extract/check | ok, 14 modules |
| `node tools/lib-sync/check-configloader.mjs` | 11 copies, 0 undeclared deviations |
| `tools/release/test-contracts.sh` / `test-publish.sh` | 15 / 13 passed |
| `bash -n` gate, `qmlformat` ConfigLoader, `git diff --check` | ok |

Open:

- Owner install as before (`iimod install modules/idle_modes
  --allow-patches`, copy the gate again). Per the re-review, the deployed
  gate is still an older copy.
- androlink `plans/features-2026-11-17.md` (§Idle gate) should mention the
  release grace and the sleep check. That file is outside this repo.
