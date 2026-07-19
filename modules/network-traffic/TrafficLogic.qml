import QtQuick
import Quickshell.Io

/*
 * Polling logic instance (NOT a singleton — IIMP modules pass instances).
 * Reads /proc/net/dev, exposes rates, boot totals, and rate histories.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // Wired from ConfigLoader by the entry component.
    property int updateInterval: 2000
    property string excludeRegex: "^(lo|docker.*|veth.*|br-.*|virbr.*|tun.*|tap.*|wg.*|tailscale.*|CloudflareWARP)$"

    property real downSpeed: 0 // bytes/s
    property real upSpeed: 0 // bytes/s
    property real totalRx: 0 // bytes since boot
    property real totalTx: 0 // bytes since boot
    property var previousStats

    readonly property int historyLength: 60
    property list<real> downHistory: []
    property list<real> upHistory: []

    function format(bytesPerSec, full) {
        let v = bytesPerSec
        let unit = "B"
        if (v >= 1024 * 1024 * 1024) {
            v /= 1024 * 1024 * 1024
            unit = "G"
        } else if (v >= 1024 * 1024) {
            v /= 1024 * 1024
            unit = "M"
        } else if (v >= 1024) {
            v /= 1024
            unit = "K"
        }
        const num = (v < 10 && unit !== "B") ? v.toFixed(1) : Math.round(v).toString()
        if (!full) return `${num}${unit}`
        return unit === "B" ? `${num} B/s` : `${num} ${unit}B/s`
    }

    function formatTotal(bytes) {
        const s = format(bytes, false)
        return s.endsWith("B") ? s : s + "B"
    }

    function updateHistories() {
        downHistory = [...downHistory, downSpeed]
        if (downHistory.length > historyLength) {
            downHistory.shift()
        }
        upHistory = [...upHistory, upSpeed]
        if (upHistory.length > historyLength) {
            upHistory.shift()
        }
    }

    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            fileNetDev.reload()

            const exclude = new RegExp(root.excludeRegex)
            const textNetDev = fileNetDev.text()
            let rx = 0
            let tx = 0
            for (const line of textNetDev.split("\n")) {
                const match = line.match(/^\s*(\S+?):\s*(\d+)(?:\s+\d+){7}\s+(\d+)/)
                if (!match || exclude.test(match[1])) continue
                rx += Number(match[2])
                tx += Number(match[3])
            }

            const now = Date.now()
            if (root.previousStats && now > root.previousStats.time) {
                const elapsed = (now - root.previousStats.time) / 1000
                root.downSpeed = Math.max(0, (rx - root.previousStats.rx) / elapsed)
                root.upSpeed = Math.max(0, (tx - root.previousStats.tx) / elapsed)
            }
            root.previousStats = { rx, tx, time: now }
            root.totalRx = rx
            root.totalTx = tx

            root.updateHistories()
            interval = root.updateInterval
        }
    }

    FileView { id: fileNetDev; path: "/proc/net/dev" }
}
