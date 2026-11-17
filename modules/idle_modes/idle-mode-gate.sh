#!/usr/bin/env bash
# hypridle suspend gate for the idle_modes IIMP module (ii sidebar three-state
# "Keep awake" tile). hypridle.conf points $suspend_cmd here and runs `resume`
# from the same listener's on-resume:
#   $suspend_cmd = ~/.config/hypr/custom/scripts/idle-mode-gate.sh suspend
#   on-resume = ~/.config/hypr/custom/scripts/idle-mode-gate.sh resume
# Suspends only in mode "off". "half" keeps lock and screen-off but never
# suspends; "full" never reaches hypridle (the Wayland idle inhibitor is on).
# A missing or unreadable mode counts as "off", the stock behaviour.
#
# In mode "off" it also holds the idle suspend while androlink reports work
# that a suspend would cut off: a fresh $XDG_RUNTIME_DIR/androlink/status.json
# (version 1, running, written within keepAwakeMaxAgeSecs or three of the
# file's own heartbeat_s, whichever is longer) with a non-empty keep_awake
# list ("mic", "webcam", "transfer"), and the PC on AC power or its battery at
# or above keepAwakeBatteryFloor percent. Anything missing or invalid falls
# back to the plain mode check. Only this idle suspend is held: locking, lid
# close, the ii Sleep menu and low-battery suspend are unchanged.
#
# A hold is not decided once: the gate waits and checks again every
# keepAwakeRecheckSecs, and suspends as soon as the hold no longer applies or
# after keepAwakeMaxHoldMins. When only keep_awake empties (a call's mic or
# camera reconnecting, the next queued transfer), it suspends only once the
# list stayed empty at every check for keepAwakeReleaseGraceSecs. The wait
# ends without a suspend when `resume` runs (input), when the mode leaves
# "off", or when a screen is on again (the sign of input when hypridle.conf
# lacks the on-resume line). The waiting gate's PID is in
# $XDG_RUNTIME_DIR/idle-mode-gate.pid (0600, locked).
#
# Prints one line with the decision and its reasons, and one more when a wait
# ends. Usage: idle-mode-gate.sh suspend [--dry-run] | idle-mode-gate.sh resume
set -u

config_file="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/modules/idle_modes.json"
# Overridable for tests only; the kernel's power supply class otherwise.
power_dir="${IDLE_MODES_POWER_SUPPLY_DIR:-/sys/class/power_supply}"

# Module option defaults and ranges (the shell's ConfigLoader heals the same
# ranges; the script clamps on its own because it can run before the shell).
floor_default=20 floor_min=0 floor_max=100
max_age_default=90 max_age_min=15 max_age_max=3600
recheck_default=60 recheck_min=15 recheck_max=600
max_hold_default=120 max_hold_min=1 max_hold_max=1440
grace_default=45 grace_min=15 grace_max=600
# androlink's own heartbeat range (status.heartbeat_s); outside it the
# file's value is ignored.
heartbeat_min=1 heartbeat_max=3600
# Larger status files are not androlink's; don't parse them.
status_max_bytes=65536

hold_file=""
[[ "${XDG_RUNTIME_DIR:-}" == /* ]] && hold_file="$XDG_RUNTIME_DIR/idle-mode-gate.pid"
sleeper=""

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

read_mode() {
    local mode
    mode=$(jq -r '.mode // "off"' "$config_file" 2>/dev/null) || mode=off
    case "$mode" in
        off | half | full) printf '%s' "$mode" ;;
        *) printf off ;;
    esac
}

# First line of a small sysfs-style file, or empty.
read_line() {
    local line=""
    IFS= read -r line 2>/dev/null <"$1" || true
    printf '%s' "$line"
}

# Power source summary: "ac", "battery <percent>", "no-battery" (the power
# supply class was read and lists no system battery and no mains supply, e.g.
# a desktop) or "unknown" (the class can't be read, a battery's charge can't
# be read, or a mains supply is offline with no battery in sight).
# Peripheral batteries (scope Device: mice, headsets) and USB-C partner
# supplies are ignored. With several system batteries the charge is their
# mean.
power_state() {
    local entry name type scope capacity ac=0 mains=0 batteries=0 readable=0 sum=0
    if ! [ -d "$power_dir" ] || ! [ -r "$power_dir" ] || ! [ -x "$power_dir" ]; then
        echo unknown
        return
    fi
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
                mains=1
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
    elif ((batteries > 0 || mains)); then
        # A battery without a level, or an offline mains supply with no
        # battery visible: a portable PC whose charge can't be known.
        echo unknown
    else
        echo no-battery
    fi
}

# androlink's keep-awake reasons: "fresh <codes>" (comma-separated, possibly
# empty) or "missing" | "invalid" | "stopped" | "stale".
androlink_state() { # max_age_secs now_secs
    local runtime="${XDG_RUNTIME_DIR:-}" file parsed updated beats reasons size age limit
    # Without an absolute XDG_RUNTIME_DIR androlink writes no status file.
    [[ "$runtime" == /* ]] || { echo missing; return; }
    file="$runtime/androlink/status.json"
    [ -f "$file" ] || { echo missing; return; }
    size=$(wc -c 2>/dev/null <"$file") || { echo invalid; return; }
    ((size > 0 && size <= status_max_bytes)) || { echo invalid; return; }
    # Exactly one JSON object. Reason codes are kept only when they look like
    # codes, so the log line never carries anything else; duplicates are
    # dropped and the order is fixed. A missing or null keep_awake is none.
    # A heartbeat_s in androlink's range gives three heartbeats (0 if not).
    parsed=$(jq -r -s --argjson hmin "$heartbeat_min" --argjson hmax "$heartbeat_max" '
        if length != 1 then "invalid" else .[0] |
        if type != "object" or .version != 1 then "invalid"
        elif (.updated | type) != "number" or .updated <= 0 or .updated >= 1e11 then "invalid"
        elif .running != true then "stopped"
        elif ((.keep_awake // []) | type) != "array" then "invalid"
        else "\(.updated | floor) \(.heartbeat_s
                | if type == "number" and . >= $hmin and . <= $hmax then . * 3 | ceil else 0 end) \([(.keep_awake // [])[]
            | select(type == "string" and test("\\A[a-z][a-z0-9_]{0,31}\\z"))] | unique | .[:8] | join(","))"
        end end' "$file" 2>/dev/null) || { echo invalid; return; }
    case "$parsed" in
        invalid | stopped)
            echo "$parsed"
            return
            ;;
    esac
    read -r updated beats reasons <<<"$parsed"
    [[ "$updated" =~ ^[0-9]{1,11}$ && "$beats" =~ ^[0-9]{1,5}$ && "${reasons:-}" =~ ^[a-z0-9_,]*$ ]] || {
        echo invalid
        return
    }
    # The option, widened to three of androlink's heartbeats when it says it
    # writes less often.
    limit=$1
    ((beats > limit)) && limit=$beats
    age=$(($2 - updated))
    # Older than the limit, or ahead of this clock by more than one heartbeat
    # (a third of the limit): androlink's own staleness rule.
    if ((age > limit || age < -(limit / 3))); then
        echo stale
        return
    fi
    echo "fresh ${reasons:-}"
}

# Whether androlink holds the idle suspend right now: sets hold (1 or 0),
# empty (1 when keep_awake is empty in a fresh status file and the power
# source would let a reason hold: a reason coming back would hold again) and
# why (the reasons, for the log line). Reads the options on every call.
decide() {
    local floor max_age now state reasons power level power_ok=0 power_why
    floor=$(read_option keepAwakeBatteryFloor "$floor_default" "$floor_min" "$floor_max")
    max_age=$(read_option keepAwakeMaxAgeSecs "$max_age_default" "$max_age_min" "$max_age_max")
    now=${EPOCHSECONDS:-$(date +%s)}
    hold=0 empty=0
    read -r state reasons <<<"$(androlink_state "$max_age" "$now")"
    if [ "$state" != fresh ]; then
        why="androlink status $state"
        return
    fi
    power=$(power_state)
    case "$power" in
        ac)
            power_ok=1
            power_why="on AC"
            ;;
        no-battery)
            power_ok=1
            power_why="no battery"
            ;;
        "battery "*)
            level=${power#battery }
            if ((level >= floor)); then
                power_ok=1
                power_why="battery $level% (floor $floor%)"
            else
                power_why="battery $level% below floor $floor%"
            fi
            ;;
        *)
            power_why="battery level unknown"
            ;;
    esac
    if [ -n "${reasons:-}" ]; then
        hold=$power_ok
        why="androlink keep_awake $reasons, $power_why"
    elif ((power_ok)); then
        empty=1
        why="androlink keep_awake none"
    else
        why="androlink keep_awake none, $power_why"
    fi
}

# True while every screen is off: hypridle's screen-off listener ran and
# there has been no input since. No answer, or no screen, counts as on.
screens_off() {
    local monitors
    monitors=$(timeout 5 hyprctl monitors -j 2>/dev/null) || return 1
    [ "$(jq -r 'if type == "array" and length > 0 and all(.[]; .dpmsStatus == false)
        then "off" else "on" end' <<<"$monitors" 2>/dev/null)" = off ]
}

# True when XDG_RUNTIME_DIR is this user's directory and nobody else can
# write to it, so the hold file in it can be trusted.
runtime_private() {
    local dir="${XDG_RUNTIME_DIR:-}" perms
    [[ "$dir" == /* ]] && [ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] || return 1
    perms=$(stat -c %a -- "$dir" 2>/dev/null) || return 1
    [[ "$perms" =~ ^[0-7]{3,4}$ ]] && (((8#$perms & 8#022) == 0))
}

# True when PID is this user's idle-mode-gate.sh running `suspend`.
is_waiting_gate() { # pid
    local arg prev=""
    [ -O "/proc/$1" ] || return 1
    while IFS= read -r -d '' arg; do
        if [[ "$prev" == idle-mode-gate.sh || "$prev" == */idle-mode-gate.sh ]] && [ "$arg" = suspend ]; then
            return 0
        fi
        prev=$arg
    done 2>/dev/null <"/proc/$1/cmdline"
    return 1
}

# Stops the gate that waits in `suspend`: the one holding the lock on the
# hold file, which wrote its PID there. A hold file nobody locks is a
# leftover and is removed. Returns 0 when a waiting gate was stopped.
cancel_holder() {
    local fd pid
    [ -n "$hold_file" ] && [ -f "$hold_file" ] && [ ! -L "$hold_file" ] && [ -O "$hold_file" ] || return 1
    exec {fd}<"$hold_file" || return 1
    if flock -n "$fd"; then
        exec {fd}<&-
        rm -f -- "$hold_file"
        return 1
    fi
    IFS= read -r pid <&"$fd" || pid=""
    exec {fd}<&-
    [[ "$pid" =~ ^[1-9][0-9]{0,9}$ ]] && is_waiting_gate "$pid" || return 1
    # Without the file the wait also ends at its next check, should the
    # signal be lost.
    rm -f -- "$hold_file"
    kill -TERM "$pid" 2>/dev/null
    return 0
}

# Removes the hold file while it still names this gate.
release_hold() {
    [ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null
    sleeper=""
    [ "$(read_line "$hold_file")" = "$$" ] && rm -f -- "$hold_file"
}

# Waits while androlink holds the idle suspend and returns when the PC should
# suspend now ($why says why). Exits without suspending when the wait can't
# be kept safely or is cancelled, the mode leaves "off" or a screen is on.
wait_while_held() {
    local fd recheck max_hold grace held=0 wait_secs empty_for=-1
    recheck=$(read_option keepAwakeRecheckSecs "$recheck_default" "$recheck_min" "$recheck_max")
    max_hold=$(read_option keepAwakeMaxHoldMins "$max_hold_default" "$max_hold_min" "$max_hold_max")
    grace=$(read_option keepAwakeReleaseGraceSecs "$grace_default" "$grace_min" "$grace_max")
    if ! runtime_private; then
        echo "idle-mode-gate: mode off, $why, not suspending (no private XDG_RUNTIME_DIR to wait in)"
        exit 0
    fi
    umask 077
    if [ -L "$hold_file" ] || { [ -e "$hold_file" ] && ! { [ -f "$hold_file" ] && [ -O "$hold_file" ]; }; }; then
        echo "idle-mode-gate: mode off, $why, not suspending (the hold file is not the gate's)"
        exit 0
    fi
    if ! exec {fd}>>"$hold_file"; then
        echo "idle-mode-gate: mode off, $why, not suspending (the hold file can't be written)"
        exit 0
    fi
    if ! flock -n "$fd"; then
        # A gate from an earlier idle period still waits (hypridle.conf
        # without the on-resume line): this idle period replaces it.
        cancel_holder
        exec {fd}>&-
        if ! { exec {fd}>>"$hold_file"; } 2>/dev/null || ! flock -w 5 "$fd"; then
            echo "idle-mode-gate: mode off, $why, not suspending (another gate is waiting)"
            exit 0
        fi
    fi
    printf '%s\n' "$$" >"$hold_file"
    chmod 600 -- "$hold_file" 2>/dev/null
    trap release_hold EXIT
    trap 'release_hold; echo "idle-mode-gate: input, not suspending"; exit 0' TERM INT HUP
    echo "idle-mode-gate: mode off, $why, not suspending, checking again every $recheck s for up to $max_hold min"
    while :; do
        # The next check comes after recheck seconds, or when the release
        # grace or the hold limit ends if that is sooner, so neither is
        # overshot.
        wait_secs=$recheck
        ((empty_for >= 0 && grace - empty_for < wait_secs)) && wait_secs=$((grace - empty_for))
        ((max_hold * 60 - held < wait_secs)) && wait_secs=$((max_hold * 60 - held))
        # The sleep gets no copy of the locked hold file, so it can't keep
        # the lock after the gate is killed outright (SIGKILL, OOM).
        sleep "$wait_secs" {fd}>&- &
        sleeper=$!
        wait "$sleeper"
        sleeper=""
        held=$((held + wait_secs))
        if [ "$(read_line "$hold_file")" != "$$" ]; then
            echo "idle-mode-gate: wait cancelled, not suspending"
            exit 0
        fi
        mode=$(read_mode)
        if [ "$mode" != off ]; then
            echo "idle-mode-gate: mode $mode, not suspending"
            exit 0
        fi
        if ! screens_off; then
            echo "idle-mode-gate: a screen is on, not suspending"
            exit 0
        fi
        decide
        if ((hold)); then
            empty_for=-1
        elif ((empty)); then
            # keep_awake is empty in a fresh file: a reason may be about to
            # come back (androlink drops mic and webcam while a stream
            # reconnects). Suspend only once it stayed empty at every check
            # for the whole grace; any reason back starts the grace anew.
            if ((empty_for < 0)); then
                empty_for=0
            else
                empty_for=$((empty_for + wait_secs))
            fi
            if ((empty_for >= grace)); then
                why="$why for $empty_for s"
                break
            fi
        else
            # Stale, stopped, missing or invalid status, or the battery below
            # the floor or unreadable: no grace.
            break
        fi
        if ((held >= max_hold * 60)); then
            why="$why, held $max_hold min (the limit)"
            break
        fi
    done
    release_hold
}

case "${1:-}" in
    suspend)
        dry_run=0
        [ "${2:-}" = --dry-run ] && dry_run=1
        mode=$(read_mode)
        if [ "$mode" != off ]; then
            echo "idle-mode-gate: mode $mode, not suspending"
            exit 0
        fi

        decide
        if ((hold)); then
            if ((dry_run)); then
                echo "idle-mode-gate: mode off, $why, not suspending"
                exit 0
            fi
            wait_while_held
        elif ((dry_run)); then
            echo "idle-mode-gate: mode off, $why, would suspend"
            exit 0
        fi
        echo "idle-mode-gate: mode off, $why, suspending"
        systemctl suspend || loginctl suspend
        ;;
    resume)
        if cancel_holder; then
            echo "idle-mode-gate: resume, stopped the waiting gate"
        else
            echo "idle-mode-gate: resume, nothing waiting"
        fi
        ;;
    *)
        echo "usage: idle-mode-gate.sh suspend [--dry-run] | idle-mode-gate.sh resume" >&2
        exit 2
        ;;
esac
