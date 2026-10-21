# idle_modes - three-state "Keep awake" tile

Tier B module that turns the sidebar "Keep awake" tile into a three-state
idle mode and restores the chosen mode after a reboot or shell restart. It
patches the stock `Idle` service and the tile model; the suspend part is
enforced by a small hypridle gate script outside the shell tree.

> [!IMPORTANT]
> Suspend gating lives in `~/.config/hypr/hypridle.conf`, which dots-hyprland
> updates overwrite. Re-apply the one-line `$suspend_cmd` change after every
> dots update (see Installation), or "half" mode will suspend again.

## Interaction

Clicking the tile cycles the modes in this order:

| Mode | Tile | Lock (5 min) | Screen off (10 min) | Suspend (15 min) |
| --- | --- | --- | --- | --- |
| off | `coffee`, not highlighted, "Sleeps when idle" | yes | yes | yes |
| half | `bedtime_off`, highlighted, "Screen off only" | yes | yes | no |
| full | `coffee`, highlighted, "Always on" | no | no | no |

The lock screen's "unlock and keep awake" action switches to full. The
battery auto-suspend at the critical level is not affected by any mode.

## Requirements

| Dependency | Use |
| --- | --- |
| hypridle | idle timers; its suspend listener calls the gate script |
| jq | the gate script reads the mode from the module config |
| Android-style quick panel | the tile model patch; the classic-style button still cycles but only highlights in full mode |

## Installation

From the repository root:

```bash
iimod validate modules/idle_modes
iimod check modules/idle_modes
iimod install modules/idle_modes --allow-patches
```

Install the gate script and point hypridle at it (once, and again after each
dots-hyprland update for the `hypridle.conf` line):

```bash
install -Dm755 modules/idle_modes/idle-mode-gate.sh ~/.config/hypr/custom/scripts/idle-mode-gate.sh
sed -i 's|^\$suspend_cmd = .*|$suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend|' ~/.config/hypr/hypridle.conf
pkill -x hypridle; hyprctl dispatch 'hl.dsp.exec_cmd("hypridle")'
```

Restart hypridle through Hyprland as shown, so it does not run inside a
terminal's process group.

## Configuration

Settings path: `~/.config/illogical-impulse/modules/idle_modes.json`.

| Key | Default | Description |
| --- | --- | --- |
| `mode` | `"off"` | `"off"`, `"half"` or `"full"`; invalid values heal to `"off"` |

The tile writes this file on every change, and hand edits apply live.

## Data and behavior

- The window entry loads the mode at shell start and calls `Idle.setIdleMode`,
  which also syncs the stock `Persistent.states.idle.inhibit` flag.
- "full" uses the stock Wayland idle inhibitor, so hypridle sees no idleness.
- "half" and "off" leave hypridle running; the gate script suspends only when
  the file says `"off"` (missing, unreadable or invalid also means `"off"`).
- `idle-mode-gate.sh suspend --dry-run` prints the decision without suspending.

## Limitations

- The classic-style quick toggle button is not patched: it cycles the mode
  but only shows the highlighted state for full.
- Changing the lock or screen-off timeouts still means editing `hypridle.conf`.

## Implementation notes

Patches (insert-only): `services/Idle.qml` gets `idleMode`, `idleModesActive`,
`setIdleMode()` and `cycleIdleMode()`, and `toggleInhibit()` routes through the
mode while the module is active. `IdleInhibitorToggle.qml` gets an id and four
`Binding`s (`toggled`, `icon`, `statusText`, `tooltipText`) gated on
`Idle.idleModesActive`, so the stock look returns if the entry is not loaded.
