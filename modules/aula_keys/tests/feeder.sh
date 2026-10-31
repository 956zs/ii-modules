#!/usr/bin/env bash
# Fake `aulactl feed` for development: prints contract lines (aulactl
# docs/feed.md) without a keyboard. Accepts the same argv as the module
# passes (`feed --keys KeyZ,KeyX [--depth-hz N]`) and alternates presses
# across the keys at about FEEDER_KPS presses per second. Exits 0 on
# SIGTERM/SIGINT like the real feed.
#
# FEEDER_HOLD="KeyZ:1.70:press,KeyX:0" freezes the given depths (and
# presses) after the hello instead of animating, for screenshots.
set -u

keys="KeyZ,KeyX"
while [ $# -gt 0 ]; do
    case "$1" in
    --keys) keys="${2:-$keys}"; shift 2 ;;
    --depth-hz) shift 2 ;;
    *) shift ;;
    esac
done
IFS=',' read -r -a codes <<<"$keys"
kps="${FEEDER_KPS:-8}"

trap 'exit 0' TERM INT
start="${EPOCHREALTIME/./}"
t() {
    local now="${EPOCHREALTIME/./}"
    local us=$((now - start))
    printf '%d.%d' $((us / 1000)) $(((us % 1000) / 100))
}

echo '{"type":"status","state":"waiting","reason":"no keyboard"}'
sleep 1
list=""
for code in "${codes[@]}"; do
    label="${code#Key}"
    label="${label#Digit}"
    list+="${list:+,}{\"code\":\"$code\",\"label\":\"$label\",\"idx\":0,\"x\":0,\"y\":0,\"w\":1,\"mode\":\"rt\",\"point\":1.00,\"press\":0.30,\"release\":0.30}"
done
echo "{\"type\":\"hello\",\"product\":\"FAKE\",\"firmware\":\"0.0.0\",\"max_mm\":3.40,\"keys\":[$list]}"

if [ -n "${FEEDER_HOLD:-}" ]; then
    IFS=',' read -r -a holds <<<"$FEEDER_HOLD"
    for hold in "${holds[@]}"; do
        IFS=':' read -r code mm action <<<"$hold"
        echo "{\"type\":\"depth\",\"t\":$(t),\"key\":\"$code\",\"mm\":$mm}"
        [ "${action:-}" = "press" ] && echo "{\"type\":\"press\",\"t\":$(t),\"key\":\"$code\"}"
    done
    while :; do
        sleep 1 &
        wait $!
    done
fi

# One press: down in four depth steps, press, up in four steps, release.
step=$(awk -v k="$kps" 'BEGIN { printf "%.3f", 1 / k / 10 }')
i=0
while :; do
    code="${codes[$((i % ${#codes[@]}))]}"
    for mm in 0.60 1.30 2.10 2.90; do
        echo "{\"type\":\"depth\",\"t\":$(t),\"key\":\"$code\",\"mm\":$mm}"
        sleep "$step"
    done
    echo "{\"type\":\"press\",\"t\":$(t),\"key\":\"$code\"}"
    sleep "$step"
    for mm in 2.20 1.40 0.50; do
        echo "{\"type\":\"depth\",\"t\":$(t),\"key\":\"$code\",\"mm\":$mm}"
        sleep "$step"
    done
    echo "{\"type\":\"release\",\"t\":$(t),\"key\":\"$code\"}"
    echo "{\"type\":\"depth\",\"t\":$(t),\"key\":\"$code\",\"mm\":0.00}"
    sleep "$step"
    i=$((i + 1))
done
