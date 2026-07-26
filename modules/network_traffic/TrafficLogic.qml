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
    // The ConfigLoader adapter, for persisted accounting. Assigning adapter
    // properties routes through the blessed ConfigLoader write path.
    property var store: null
    // ConfigLoader.ready — accounting must not initialise before the persisted
    // state has actually been read (FileView loads asynchronously).
    property bool storeReady: false

    property real downSpeed: 0 // bytes/s
    property real upSpeed: 0 // bytes/s
    property real totalRx: 0 // bytes since boot
    property real totalTx: 0 // bytes since boot
    property var previousStats

    // Rolling accounting, persisted across shell restarts and reboots.
    property real todayRx: 0
    property real todayTx: 0
    property real monthRx: 0
    property real monthTx: 0

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

    // --- persisted day/month accounting --------------------------------
    // State is one JSON-string blob (store.acctState), written by a single
    // adapter assignment: per-field flushes could be read back torn (fresh
    // day counters, stale month counters) across watchChanges reloads and
    // iimod hot reloads, which showed "this month" below "today".

    property bool acctReady: false
    property string curDayKey: ""
    property string curMonthKey: ""

    function dayKey(now) {
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    }

    function monthKey(now) {
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`
    }

    // Whatever storage said, a month contains its days. Self-heals torn or
    // otherwise impossible persisted states.
    function clampInvariant() {
        monthRx = Math.max(monthRx, todayRx)
        monthTx = Math.max(monthTx, todayTx)
    }

    function initAccounting(rx, tx) {
        const now = new Date()
        curDayKey = dayKey(now)
        curMonthKey = monthKey(now)
        let s = null
        try {
            s = JSON.parse(store.acctState)
        } catch (e) {
            s = null
        }
        const day = s?.day
        const month = s?.month
        const sample = s?.sample
        todayRx = (day && day.k === curDayKey) ? day.rx : 0
        todayTx = (day && day.k === curDayKey) ? day.tx : 0
        monthRx = (month && month.k === curMonthKey) ? month.rx : 0
        monthTx = (month && month.k === curMonthKey) ? month.tx : 0
        // Same boot (counters grew): credit the unflushed interval since the
        // last shell run. A shrunk counter means a reboot; that gap is lost by
        // design — /proc/net/dev is all we have.
        if (sample && sample.rx > 0 && rx >= sample.rx) {
            todayRx += rx - sample.rx
            todayTx += Math.max(0, tx - sample.tx)
            monthRx += rx - sample.rx
            monthTx += Math.max(0, tx - sample.tx)
        }
        clampInvariant()
        acctReady = true
        flushAccounting() // persist the repaired/credited state promptly
    }

    function accumulate(deltaRx, deltaTx) {
        const now = new Date()
        let rolled = false
        if (curDayKey !== dayKey(now)) {
            curDayKey = dayKey(now)
            todayRx = 0
            todayTx = 0
            rolled = true
        }
        if (curMonthKey !== monthKey(now)) {
            curMonthKey = monthKey(now)
            monthRx = 0
            monthTx = 0
            rolled = true
        }
        todayRx += deltaRx
        todayTx += deltaTx
        monthRx += deltaRx
        monthTx += deltaTx
        clampInvariant()
        // Persist a rollover immediately — keys and values travel together in
        // one blob, so there is no window where the file holds a new key with
        // the previous period's values.
        if (rolled) flushAccounting()
    }

    function flushAccounting() {
        if (!store || !acctReady) return
        store.acctState = JSON.stringify({
            v: 1,
            day: { k: curDayKey, rx: todayRx, tx: todayTx },
            month: { k: curMonthKey, rx: monthRx, tx: monthTx },
            sample: { rx: totalRx, tx: totalTx }
        })
    }

    // Flush at most once a minute: every JsonAdapter assignment is a config
    // file write, and the poll runs every couple of seconds.
    Timer {
        interval: 60000
        running: root.acctReady
        repeat: true
        onTriggered: root.flushAccounting()
    }

    Component.onDestruction: flushAccounting()

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
                if (root.store && root.acctReady) {
                    root.accumulate(Math.max(0, rx - root.previousStats.rx),
                                    Math.max(0, tx - root.previousStats.tx))
                }
            }
            root.previousStats = { rx, tx, time: now }
            root.totalRx = rx
            root.totalTx = tx
            // After totals: initAccounting flushes, and the flushed sample
            // must be this tick's reading.
            if (root.store && root.storeReady && !root.acctReady) {
                root.initAccounting(rx, tx)
            }

            root.updateHistories()
            interval = root.updateInterval
        }
    }

    FileView { id: fileNetDev; path: "/proc/net/dev" }
}
