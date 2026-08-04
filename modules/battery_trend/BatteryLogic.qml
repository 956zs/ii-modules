import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "BatteryAnalytics.js" as BatteryAnalytics

/*
 * Battery sampling + analytics instance (NOT a singleton — IIMP modules pass
 * instances). Data sources are all capability-free:
 *   - Quickshell.Services.UPower: percentage/state/changeRate/time estimates
 *   - FileView reads of /sys/class/power_supply/<bat>/: precise charge level,
 *     instantaneous power draw, full/design capacity, cycle count. Handles
 *     both sysfs unit families: energy_* (µWh, power_now µW) and charge_*
 *     (µAh, needs voltage_now/current_now).
 *
 * Persistence: the whole history is one JSON blob in the module config file
 * (single-assignment write, ≤ 1 flush/min — see ConfigLoader.qml). Tiered
 * retention keeps the blob bounded:
 *   raw      24 h  @ sampling interval   (sparkline, 24 h curve, regression)
 *   hourly   30 d  @ 1 h aggregates      (min/max/avg %, avg W, charge frac)
 *   daily    365 d @ 1 d aggregates      + daily health snapshots
 *   sessions last 120 plugged/unplugged segments
 *
 * Only the primary bar instance samples and persists (`sampling: true`);
 * secondary screens run in reader mode and re-derive their views from the
 * blob whenever the watched config file changes.
 *
 * Suspend/power-off shows up as a wall-clock gap between samples. Gaps are
 * kept in the data (charts break the line instead of drawing a false flat
 * segment) and excluded from awake-drain accounting, so "%/h while in use"
 * is not diluted by hours of suspend.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // Wired from ConfigLoader by the entry component.
    property var store: null
    property bool storeReady: false
    property bool sampling: false
    property int intervalSec: 60
    property bool keepHourly: true
    property bool keepDaily: true
    property bool keepSessions: true
    property string batteryName: "auto"
    // Popup/panel open: refresh the live numbers every few seconds.
    property bool fastPoll: false

    // A sample farther than this from its predecessor is a suspend/off gap.
    readonly property int gapSec: Math.max(intervalSec * 3, 300)
    readonly property int sparkSec: 3 * 3600

    // --- live state ------------------------------------------------------

    readonly property var dev: UPower.displayDevice
    readonly property bool available: dev?.isLaptopBattery ?? false
    // 0 = discharging, 1 = charging, 2 = idle on AC (full / not charging)
    readonly property int chargeClass: {
        const s = dev?.state
        if (s === UPowerDeviceState.Charging || s === UPowerDeviceState.PendingCharge)
            return 1
        if (s === UPowerDeviceState.Discharging || s === UPowerDeviceState.PendingDischarge
                || s === UPowerDeviceState.Empty)
            return 0
        return 2
    }
    readonly property bool charging: chargeClass === 1

    // sysfs charge level is finer than UPower's (often whole-percent) value;
    // the regression needs the resolution.
    property real pctSys: -1
    readonly property real pct: pctSys >= 0 ? pctSys : (dev?.percentage ?? 0) * 100

    property real smoothW: 0            // EMA of instantaneous draw, magnitude
    readonly property real upowerW: dev?.changeRate ?? 0
    readonly property real upowerSec: charging ? (dev?.timeToFull ?? 0)
                                               : (dev?.timeToEmpty ?? 0)
    property real estSec: -1            // regression estimate; -1 = unknown
    property real healthPct: -1         // full/design * 100
    property int cycles: -1

    // --- view models (rebuilt by updateViews) ----------------------------

    property var spark: []              // raw slice, last 3 h
    property var dayCurve: []           // raw, last 24 h
    property var bandDays: []           // [[day,min,max,avg]] last 30 d + today
    property var healthSeries: []       // [[day,fullPct]]
    property var sessionsRecent: []     // newest first, ≤ 8
    property var stats: ({})

    // --- history state (JS arrays, serialised as one blob) ---------------

    property bool histReady: false
    property var raw: []
    property var hourly: []
    property var daily: []
    property var sessions: []
    property var health: []
    property var hourAcc: null
    property var dayAcc: null
    property var sess: null
    property bool dirty: false
    property bool flushNow: false

    function r1(x) { return Math.round(x * 10) / 10 }
    function r2(x) { return Math.round(x * 100) / 100 }

    // --- sysfs plumbing --------------------------------------------------

    property string batDir: ""
    // 0 unknown, 1 energy_* family, 2 charge_* family
    property int family: 0
    // 0 unknown, 1 power_now, 2 current_now * voltage_now
    property int powerSource: 0

    function resolveBat() {
        let name = root.batteryName
        if (name === "auto" || name === "") {
            const devs = UPower.devices.values
            for (let i = 0; i < devs.length; i++) {
                const d = devs[i]
                if (d.isLaptopBattery && d.nativePath) {
                    name = d.nativePath
                    break
                }
            }
        }
        if (name === "auto" || name === "") {
            // UPower's device list populates asynchronously; give it a
            // moment before falling back to probing sysfs names (each miss
            // logs a warning, so the probe is the last resort).
            root.batDir = ""
            if (root.probeFallback) {
                fvProbe.idx = -1
                root.probeNext()
            } else {
                probeDelay.restart()
            }
            return
        }
        if (name.indexOf("/") >= 0)
            name = name.split("/").pop()
        root.batDir = "/sys/class/power_supply/" + name
    }

    property bool probeFallback: false
    Timer {
        id: probeDelay
        interval: 10000
        onTriggered: {
            root.probeFallback = true
            if (root.batDir === "")
                root.resolveBat()
        }
    }

    readonly property var probeNames: ["BAT0", "BAT1", "BAT2", "BATT", "CMB0", "CMB1"]
    function probeNext() {
        fvProbe.idx++
        if (fvProbe.idx < root.probeNames.length)
            fvProbe.path = "/sys/class/power_supply/" + root.probeNames[fvProbe.idx] + "/present"
    }

    onBatteryNameChanged: if (histReady) { family = 0; powerSource = 0; resolveBat() }

    function readNum(fv) {
        // `missing` short-circuits files this battery does not expose (each
        // reload of an absent path logs a warning; once is enough).
        if (!fv.path || fv.path === "" || fv.missing)
            return -1
        fv.reload()
        const n = parseInt(fv.text())
        return isNaN(n) ? -1 : n
    }

    // Refreshes the live properties and returns this instant's precise
    // percentage (or -1 when sysfs is unavailable).
    function readInstant() {
        if (root.batDir === "")
            return -1
        let now = -1
        if (root.family !== 2) {
            now = readNum(fvEnergyNow)
            if (now >= 0) root.family = 1
        }
        if (root.family !== 1) {
            now = readNum(fvChargeNow)
            if (now >= 0) root.family = 2
        }
        let full = -1
        let design = -1
        if (root.family === 1) {
            full = readNum(fvEnergyFull)
            design = readNum(fvEnergyFullDesign)
        } else if (root.family === 2) {
            full = readNum(fvChargeFull)
            design = readNum(fvChargeFullDesign)
        }
        let w = -1
        if (root.powerSource !== 2) {
            const p = readNum(fvPowerNow)
            if (p >= 0) {
                w = p / 1e6
                root.powerSource = 1
            }
        }
        if (root.powerSource !== 1) {
            const i = readNum(fvCurrentNow)
            const v = readNum(fvVoltageNow)
            if (i >= 0 && v >= 0) {
                w = (i / 1e6) * (v / 1e6)
                root.powerSource = 2
            }
        }
        if (w >= 0)
            root.smoothW = root.smoothW <= 0 ? w : 0.3 * w + 0.7 * root.smoothW
        if (full > 0 && design > 0)
            root.healthPct = full / design * 100
        const cyc = readNum(fvCycleCount)
        if (cyc > 0)
            root.cycles = cyc
        if (now >= 0 && full > 0) {
            root.pctSys = Math.min(100, now / full * 100)
            return root.pctSys
        }
        return -1
    }

    // --- sampling --------------------------------------------------------

    function sampleNow() {
        if (!root.sampling || !root.histReady)
            return
        const t = Math.floor(Date.now() / 1000)
        let p = readInstant()
        // FileView.reload() is asynchronous. A transient sysfs read miss must
        // not alternate the precise value with UPower's rounded percentage;
        // retain the last coherent sysfs sample and only use UPower before the
        // first successful sysfs read.
        if (p < 0 && root.pctSys >= 0)
            p = root.pctSys
        if (p < 0 && root.available)
            p = (root.dev.percentage ?? 0) * 100
        if (p < 0)
            return
        const w = root.smoothW > 0 ? root.smoothW : Math.abs(root.upowerW)
        appendSample(t, p, w, root.chargeClass)
        root.estSec = computeEstimate(t)
    }

    function appendSample(t, p, w, c) {
        const last = raw.length > 0 ? raw[raw.length - 1] : null
        const dt = last ? t - last[0] : 0
        // Same-second duplicate (state-change trigger racing the timer).
        if (last && dt <= 0)
            return
        const awake = last !== null && dt <= root.gapSec
        rollBuckets(t)
        accInto(root.hourAcc, p, w, c, awake ? dt : 0, awake ? last[1] : -1)
        accInto(root.dayAcc, p, w, c, awake ? dt : 0, awake ? last[1] : -1)
        updateSession(t, p, c, awake, last)
        raw.push([t, r1(p), r2(w), c])
        const cutoff = t - 86400
        while (raw.length > 0 && (raw[0][0] < cutoff || raw.length > 3000))
            raw.shift()
        root.dirty = true
        if (root.flushNow) {
            flush()
            root.flushNow = false
        }
        updateViews()
    }

    function newAcc(t) {
        return { t: t, n: 0, mn: 999, mx: -1, sum: 0,
                 wSum: 0, wN: 0, chg: 0, awake: 0, dis: 0, disSec: 0 }
    }

    function accInto(a, p, w, c, dtAwake, lastP) {
        if (!a) return
        a.n++
        a.mn = Math.min(a.mn, p)
        a.mx = Math.max(a.mx, p)
        a.sum += p
        if (c === 0 && w > 0.05) {
            a.wSum += w
            a.wN++
        }
        a.awake += dtAwake
        if (c === 1) a.chg += dtAwake
        if (c === 0) {
            a.disSec += dtAwake
            // Awake-only drain: a drop across a gap is suspend drain and must
            // not inflate the in-use rate (dtAwake is 0 across gaps).
            if (dtAwake > 0 && lastP > p)
                a.dis += lastP - p
        }
    }

    function finalizeAcc(a) {
        return [a.t, r1(a.mn), r1(a.mx), r1(a.sum / a.n),
                a.wN > 0 ? r2(a.wSum / a.wN) : 0,
                a.awake > 0 ? r2(a.chg / a.awake) : 0,
                r1(a.dis), Math.round(a.disSec)]
    }

    function localDayStart(t) {
        const d = new Date(t * 1000)
        return Math.floor(new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() / 1000)
    }

    function rollBuckets(t) {
        const h = Math.floor(t / 3600) * 3600
        if (!root.hourAcc || root.hourAcc.t !== h) {
            if (root.hourAcc && root.hourAcc.n > 0 && root.keepHourly) {
                hourly.push(finalizeAcc(root.hourAcc))
                const cut = t - 30 * 86400
                while (hourly.length > 0 && hourly[0][0] < cut)
                    hourly.shift()
            }
            root.hourAcc = newAcc(h)
        }
        const d = localDayStart(t)
        if (!root.dayAcc || root.dayAcc.t !== d) {
            if (root.dayAcc && root.dayAcc.n > 0 && root.keepDaily) {
                daily.push(finalizeAcc(root.dayAcc))
                const cut = t - 365 * 86400
                while (daily.length > 0 && daily[0][0] < cut)
                    daily.shift()
            }
            if (root.keepDaily)
                healthSnapshot(d, t)
            root.dayAcc = newAcc(d)
            // Rollovers persist immediately: keys and values travel together
            // in one blob, so no window holds mixed-period state.
            root.flushNow = true
        }
    }

    function healthSnapshot(d, t) {
        if (root.healthPct <= 0)
            return
        if (health.length > 0 && health[health.length - 1][0] === d)
            return
        health.push([d, r1(root.healthPct), root.cycles])
        const cut = t - 365 * 86400
        while (health.length > 0 && health[0][0] < cut)
            health.shift()
    }

    // Sessions: alternating plugged ("c") / on-battery ("d") segments,
    // closed on a power transition or across a suspend gap.
    function updateSession(t, p, c, awake, last) {
        if (!root.keepSessions) {
            root.sess = null
            return
        }
        const k = c === 0 ? "d" : "c"
        if (!root.sess) {
            root.sess = { k: k, t0: t, p0: r1(p) }
            return
        }
        if (root.sess.k !== k || !awake) {
            if (last && last[0] > root.sess.t0 + 60) {
                sessions.push([root.sess.k, root.sess.t0, last[0], root.sess.p0, last[1]])
                while (sessions.length > 120)
                    sessions.shift()
                root.flushNow = true
            }
            root.sess = { k: k, t0: t, p0: r1(p) }
        }
    }

    // --- persistence -----------------------------------------------------

    function flush() {
        if (!root.store || !root.histReady || !root.sampling)
            return
        root.store.histState = JSON.stringify({
            v: 1,
            raw: raw, hourly: hourly, daily: daily,
            sessions: sessions, health: health,
            cur: { h: root.hourAcc, d: root.dayAcc, s: root.sess }
        })
        root.dirty = false
    }

    function loadFromBlob() {
        let s = null
        try {
            s = JSON.parse(root.store.histState)
        } catch (e) {
            s = null
        }
        raw = Array.isArray(s?.raw) ? s.raw : []
        hourly = Array.isArray(s?.hourly) ? s.hourly : []
        daily = Array.isArray(s?.daily) ? s.daily : []
        sessions = Array.isArray(s?.sessions) ? s.sessions : []
        health = Array.isArray(s?.health) ? s.health : []
        root.hourAcc = BatteryAnalytics.validAccumulator(s?.cur?.h) ? s.cur.h : null
        root.dayAcc = BatteryAnalytics.validAccumulator(s?.cur?.d) ? s.cur.d : null
        root.sess = BatteryAnalytics.validSessionAccumulator(s?.cur?.s) ? s.cur.s : null
        root.histReady = true
        updateViews()
    }

    onStoreReadyChanged: {
        if (root.storeReady && !root.histReady) {
            resolveBat()
            loadFromBlob()
        }
    }
    // Primary election can settle after the store loads (screens attach
    // asynchronously); adopt the in-progress accumulators then.
    onSamplingChanged: {
        if (root.sampling && root.histReady)
            loadFromBlob()
    }

    // Reader mode: follow the owner's flushes through the watched file.
    Connections {
        target: root.store
        function onHistStateChanged() {
            if (!root.sampling && root.histReady)
                root.loadFromBlob()
        }
    }

    // --- analysis --------------------------------------------------------

    // Honest time-remaining: least-squares slope of the precise charge level
    // over the last 30 min of contiguous same-state samples. Returns seconds,
    // -1 when there is not enough data to be honest about it.
    function computeEstimate(t) {
        const c = root.chargeClass
        if (c === 2 || raw.length === 0)
            return -1
        const win = 30 * 60
        const pts = []
        for (let i = raw.length - 1; i >= 0; i--) {
            const s = raw[i]
            if (s[3] !== c)
                break
            if (pts.length > 0 && pts[pts.length - 1][0] - s[0] > root.gapSec)
                break
            if (t - s[0] > win)
                break
            pts.push([s[0], s[1]])
        }
        if (pts.length < 5)
            return -1
        let sx = 0, sy = 0, sxx = 0, sxy = 0
        const n = pts.length
        for (let i = 0; i < n; i++) {
            const x = pts[i][0] - t
            const y = pts[i][1]
            sx += x; sy += y; sxx += x * x; sxy += x * y
        }
        const denom = n * sxx - sx * sx
        if (denom === 0)
            return -1
        const slope = (n * sxy - sx * sy) / denom // pct per second
        if (c === 0 && slope < -1e-5)
            return Math.min(root.pct / -slope, 48 * 3600)
        if (c === 1 && slope > 1e-5)
            return Math.min((100 - root.pct) / slope, 48 * 3600)
        return -1
    }

    function computeStats(t) {
        return BatteryAnalytics.computeStats(t, root.daily, root.hourly, root.raw,
                                             root.gapSec, root.dayAcc,
                                             root.sessions, root.health)
    }

    function updateViews() {
        const t = Math.floor(Date.now() / 1000)
        root.dayCurve = raw.slice()
        root.spark = raw.filter(s => s[0] >= t - root.sparkSec)
        let band = []
        const cut = t - 30 * 86400
        for (let i = 0; i < daily.length; i++) {
            const e = daily[i]
            if (e[0] >= cut)
                band.push([e[0], e[1], e[2], e[3]])
        }
        if (root.dayAcc && root.dayAcc.n > 0)
            band.push([root.dayAcc.t, r1(root.dayAcc.mn), r1(root.dayAcc.mx),
                       r1(root.dayAcc.sum / root.dayAcc.n)])
        root.bandDays = band
        root.healthSeries = health.map(e => [e[0], e[1]])
        root.sessionsRecent = sessions.slice(-8).reverse()
        root.stats = computeStats(t)
    }

    // --- formatting helpers (shared by popup/panel) ----------------------

    function fmtW(w) {
        return w < 0 ? "—" : `${w.toFixed(1)} W`
    }

    function fmtDur(sec) {
        if (sec <= 0) return "—"
        const h = Math.floor(sec / 3600)
        const m = Math.round((sec % 3600) / 60)
        if (h > 0) return `${h} h ${m} min`
        return `${m} min`
    }

    function fmtClock(t) {
        const d = new Date(t * 1000)
        return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`
    }

    function fmtDay(t) {
        const d = new Date(t * 1000)
        return `${d.getMonth() + 1}/${d.getDate()}`
    }

    // --- timers / probes -------------------------------------------------

    Timer {
        interval: Math.max(15, root.intervalSec) * 1000
        running: root.sampling && root.histReady
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sampleNow()
    }

    // Plug/unplug and state flips produce an immediate sample so session
    // boundaries land on the transition, not up to a minute later.
    Connections {
        target: root.dev
        function onStateChanged() {
            if (root.sampling && root.histReady)
                root.sampleNow()
        }
    }

    // Live numbers refresh while a popup/panel is looking at them.
    Timer {
        interval: 3000
        running: root.fastPoll
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.readInstant()
            root.estSec = root.computeEstimate(Math.floor(Date.now() / 1000))
        }
    }

    // Flush at most once a minute: every adapter assignment is a config file
    // write.
    Timer {
        interval: 60000
        running: root.sampling && root.histReady
        repeat: true
        onTriggered: if (root.dirty) root.flush()
    }

    Component.onDestruction: if (root.dirty) root.flush()

    // Battery dir autodetection fallback when UPower gives no nativePath.
    FileView {
        id: fvProbe
        property int idx: -1
        onLoaded: root.batDir = fvProbe.path.substring(0, fvProbe.path.length - "/present".length)
        onLoadFailed: root.probeNext()
    }

    component SysFile: FileView {
        property bool missing: false
        onPathChanged: missing = false
        onLoaded: missing = false
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound)
                missing = true
        }
    }

    SysFile { id: fvEnergyNow; path: root.batDir === "" ? "" : root.batDir + "/energy_now" }
    SysFile { id: fvEnergyFull; path: root.batDir === "" ? "" : root.batDir + "/energy_full" }
    SysFile { id: fvEnergyFullDesign; path: root.batDir === "" ? "" : root.batDir + "/energy_full_design" }
    SysFile { id: fvChargeNow; path: root.batDir === "" ? "" : root.batDir + "/charge_now" }
    SysFile { id: fvChargeFull; path: root.batDir === "" ? "" : root.batDir + "/charge_full" }
    SysFile { id: fvChargeFullDesign; path: root.batDir === "" ? "" : root.batDir + "/charge_full_design" }
    SysFile { id: fvPowerNow; path: root.batDir === "" ? "" : root.batDir + "/power_now" }
    SysFile { id: fvCurrentNow; path: root.batDir === "" ? "" : root.batDir + "/current_now" }
    SysFile { id: fvVoltageNow; path: root.batDir === "" ? "" : root.batDir + "/voltage_now" }
    SysFile { id: fvCycleCount; path: root.batDir === "" ? "" : root.batDir + "/cycle_count" }
}
