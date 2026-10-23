#!/usr/bin/env bash
# hypridle suspend gate for the idle_modes IIMP module (ii sidebar three-state
# "Keep awake" tile). hypridle.conf points $suspend_cmd here:
#   $suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend
# Suspends only in mode "off". "half" keeps lock and screen-off but never
# suspends; "full" never reaches hypridle (the Wayland idle inhibitor is on).
# A missing or unreadable mode counts as "off", the stock behaviour.
# Usage: idle-mode-gate.sh suspend [--dry-run]
set -u

mode_file="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/modules/idle_modes.json"

mode=$(jq -r '.mode // "off"' "$mode_file" 2>/dev/null) || mode=off
case "$mode" in
    off | half | full) ;;
    *) mode=off ;;
esac

case "${1:-}" in
    suspend)
        if [ "$mode" != off ]; then
            echo "idle-mode-gate: mode $mode, not suspending"
            exit 0
        fi
        if [ "${2:-}" = --dry-run ]; then
            echo "idle-mode-gate: mode off, would suspend"
            exit 0
        fi
        systemctl suspend || loginctl suspend
        ;;
    *)
        echo "usage: idle-mode-gate.sh suspend [--dry-run]" >&2
        exit 2
        ;;
esac
