#!/usr/bin/env bash
# hypridle suspend gate for the idle_modes IIMP module (ii sidebar three-state
# "Keep awake" tile). hypridle.conf points $suspend_cmd here:
#   $suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend
# Suspends only in mode "off". "half" keeps lock and screen-off but never
# suspends; "full" never reaches hypridle (the Wayland idle inhibitor is on).
# A missing or unreadable mode counts as "off", the stock behaviour.
#
# In mode "off" it also holds the idle suspend while androlink reports work
# that a suspend would cut off: a fresh $XDG_RUNTIME_DIR/androlink/status.json
# (version 1, running, written within keepAwakeMaxAgeSecs) with a non-empty
# keep_awake list ("mic", "webcam", "transfer"), and the PC on AC power or its
# battery at or above keepAwakeBatteryFloor percent. Anything missing or
# invalid falls back to the plain mode check. Only this idle suspend is held:
# locking, lid close, the ii Sleep menu and low-battery suspend are unchanged.
#
# Prints one line with the decision and its reasons.
# Usage: idle-mode-gate.sh suspend [--dry-run]
set -u

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/modules/idle_modes.json"
# Overridable for tests only; the kernel's power supply class otherwise.
power_dir="${IDLE_MODES_POWER_SUPPLY_DIR:-/sys/class/power_supply}"

# Module option defaults and ranges (the shell's ConfigLoader heals the same
# ranges; the script clamps on its own because it can run before the shell).
floor_default=20 floor_min=0 floor_max=100
max_age_default=90 max_age_min=15 max_age_max=3600
# Larger status files are not androlink's; don't parse them.
status_max_bytes=65536

# Prints the number option `key` from the config, rounded and clamped like
# the ConfigLoader does, or the default when it is missing or not a number.
read_option() { # key default min max
    local value
    value=$(jq -r --arg key "$1" --argjson low "$3" --argjson high "$4" \
        '.[$key] | select(type == "number") | ([([., $low] | max), $high] | min) + 0.5 | floor' \
        "$config_file" 2>/dev/null) || value=""
    [[ "$value" =~ ^-?[0-9]{1,9}$ ]] || value=$2
    printf '%s' "$value"
}

# First line of a small sysfs-style file, or empty.
read_line() {
    local line=""
    IFS= read -r line 2>/dev/null <"$1" || true
    printf '%s' "$line"
}

# Power source summary: "ac", "battery <percent>", "no-battery" (no system
# battery at all, e.g. a desktop) or "unknown" (a battery whose charge can't
# be read). Peripheral batteries (scope Device: mice, headsets) and USB-C
# partner supplies are ignored. With several system batteries the charge is
# their mean.
power_state() {
    local entry name type scope capacity ac=0 batteries=0 readable=0 sum=0
    for entry in "$power_dir"/*; do
        [ -d "$entry" ] || continue
        name=${entry##*/}
        type=$(read_line "$entry/type")
        scope=$(read_line "$entry/scope")
        if [ -z "$type" ]; then
            case "$name" in
                AC* | ADP* | ACAD*) type=Mains ;;
                BAT*) type=Battery ;;
            esac
        fi
        [ "$scope" = Device ] && continue
        case "$type" in
            Mains)
                [ "$(read_line "$entry/online")" = 1 ] && ac=1
                ;;
            Battery)
                batteries=$((batteries + 1))
                capacity=$(read_line "$entry/capacity")
                if [[ "$capacity" =~ ^[0-9]{1,3}$ ]] && ((10#$capacity <= 100)); then
                    readable=$((readable + 1))
                    sum=$((sum + 10#$capacity))
                fi
                ;;
        esac
    done
    if ((ac)); then
        echo ac
    elif ((readable > 0)); then
        echo "battery $((sum / readable))"
    elif ((batteries > 0)); then
        echo unknown
    else
        echo no-battery
    fi
}

# androlink's keep-awake reasons: "fresh <codes>" (comma-separated, possibly
# empty) or "missing" | "invalid" | "stopped" | "stale".
androlink_state() { # max_age_secs now_secs
    local runtime="${XDG_RUNTIME_DIR:-}" file parsed updated reasons size age
    # Without an absolute XDG_RUNTIME_DIR androlink writes no status file.
    [[ "$runtime" == /* ]] || { echo missing; return; }
    file="$runtime/androlink/status.json"
    [ -f "$file" ] || { echo missing; return; }
    size=$(wc -c 2>/dev/null <"$file") || { echo invalid; return; }
    ((size > 0 && size <= status_max_bytes)) || { echo invalid; return; }
    # Exactly one JSON object. Reason codes are kept only when they look like
    # codes, so the log line never carries anything else; duplicates are
    # dropped and the order is fixed. A missing or null keep_awake is none.
    parsed=$(jq -r -s '
        if length != 1 then "invalid" else .[0] |
        if type != "object" or .version != 1 then "invalid"
        elif (.updated | type) != "number" or .updated <= 0 or .updated >= 1e11 then "invalid"
        elif .running != true then "stopped"
        elif ((.keep_awake // []) | type) != "array" then "invalid"
        else "\(.updated | floor) \([(.keep_awake // [])[]
            | select(type == "string" and test("\\A[a-z][a-z0-9_]{0,31}\\z"))] | unique | .[:8] | join(","))"
        end end' "$file" 2>/dev/null) || { echo invalid; return; }
    case "$parsed" in
        invalid | stopped)
            echo "$parsed"
            return
            ;;
    esac
    read -r updated reasons <<<"$parsed"
    [[ "$updated" =~ ^[0-9]{1,11}$ && "${reasons:-}" =~ ^[a-z0-9_,]*$ ]] || { echo invalid; return; }
    age=$(($2 - updated))
    # Older than the limit, or ahead of this clock by more than one heartbeat
    # (a third of the limit): androlink's own staleness rule.
    if ((age > $1 || age < -($1 / 3))); then
        echo stale
        return
    fi
    echo "fresh ${reasons:-}"
}

mode=$(jq -r '.mode // "off"' "$config_file" 2>/dev/null) || mode=off
case "$mode" in
    off | half | full) ;;
    *) mode=off ;;
esac

case "${1:-}" in
    suspend)
        dry_run=0
        [ "${2:-}" = --dry-run ] && dry_run=1
        if [ "$mode" != off ]; then
            echo "idle-mode-gate: mode $mode, not suspending"
            exit 0
        fi

        floor=$(read_option keepAwakeBatteryFloor "$floor_default" "$floor_min" "$floor_max")
        max_age=$(read_option keepAwakeMaxAgeSecs "$max_age_default" "$max_age_min" "$max_age_max")
        now=${EPOCHSECONDS:-$(date +%s)}
        hold=0
        read -r state reasons <<<"$(androlink_state "$max_age" "$now")"
        if [ "$state" != fresh ]; then
            why="androlink status $state"
        elif [ -z "${reasons:-}" ]; then
            why="androlink keep_awake none"
        else
            power=$(power_state)
            case "$power" in
                ac)
                    hold=1
                    why="androlink keep_awake $reasons, on AC"
                    ;;
                no-battery)
                    hold=1
                    why="androlink keep_awake $reasons, no battery"
                    ;;
                "battery "*)
                    level=${power#battery }
                    if ((level >= floor)); then
                        hold=1
                        why="androlink keep_awake $reasons, battery $level% (floor $floor%)"
                    else
                        why="androlink keep_awake $reasons, battery $level% below floor $floor%"
                    fi
                    ;;
                *)
                    why="androlink keep_awake $reasons, battery level unknown"
                    ;;
            esac
        fi

        if ((hold)); then
            echo "idle-mode-gate: mode off, $why, not suspending"
            exit 0
        fi
        if ((dry_run)); then
            echo "idle-mode-gate: mode off, $why, would suspend"
            exit 0
        fi
        echo "idle-mode-gate: mode off, $why, suspending"
        systemctl suspend || loginctl suspend
        ;;
    *)
        echo "usage: idle-mode-gate.sh suspend [--dry-run]" >&2
        exit 2
        ;;
esac
