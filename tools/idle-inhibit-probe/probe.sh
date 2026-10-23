#!/usr/bin/env bash
# Asks the compositor whether a Wayland idle inhibitor is currently in effect.
# Prints INHIBITED, NOT_INHIBITED, or INCONCLUSIVE (input arrived during the
# 8 s window). Needs a compositor with ext-idle-notify-v1.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$(QT_QPA_PLATFORM=wayland timeout -s INT 8 qs -n -p "$here/shell.qml" 2>&1)
raw=$(grep -c '\[idleprobe\] raw-idle' <<<"$out")
inhibited=$(grep -c '\[idleprobe\] inhib-idle' <<<"$out")
if [ "$raw" -eq 0 ]; then
    echo INCONCLUSIVE
elif [ "$inhibited" -gt 0 ]; then
    echo NOT_INHIBITED
else
    echo INHIBITED
fi
