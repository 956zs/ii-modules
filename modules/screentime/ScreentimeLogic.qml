import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

/*
 * Focus accounting instance (NOT a singleton — IIMP modules pass instances).
 * Lives exactly once, in the window slot's Scope: the bar entry is
 * instantiated per bar (per monitor), so hosting the accountant there would
 * double-count on multi-head setups. Bar/popup consumers read the persisted
 * blob instead.
 *
 * Accounting is event-driven off Quickshell's native ToplevelManager: every
 * focus change closes out the previous app's interval. A 15s heartbeat is
 * the only timer — it exists so that suspend gaps are bounded and detectable
 * (a wall-clock jump above idleGapSec between two accounting events is
 * credited to nothing), not for display.
 *
 * Honesty rules:
 *  - GlobalStates.screenLocked pauses accounting entirely.
 *  - Jumps > idleGapSec between events (suspend, SIGSTOP, …) credit nothing.
 *  - AFK with the screen unlocked and a window focused is NOT detectable
 *    from here (no idle protocol) — documented limitation.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // Wired from ConfigLoader by the entry component.
    property var store: null
    property bool storeReady: false

    readonly property string otherKey: "__other__"
    readonly property int maxAppsPerDay: 20
    readonly property int retentionDays: 30

    readonly property int idleGapSec: (store?.idleGapSec ?? 0) > 0 ? store.idleGapSec : 90
    readonly property bool keepHistory: store?.keepHistory === true
    readonly property list<string> excluded: {
        const raw = store?.excludedApps ?? ""
        return raw.split(",").map(s => s.trim().toLowerCase()).filter(s => s.length > 0)
    }

    // --- live state (in memory, flushed to the blob at most once a minute) --
    property bool ready: false
    property string curDayKey: ""
    property var todayApps: ({})     // appId -> seconds
    property var hours: []           // 24 reals, seconds per hour of today
    property bool hoursComplete: true // false when a pre-v1.3 day lacks its early buckets
    property var days: []            // [{k, total, apps:[{n,s}]}] oldest→newest, today excluded
    property real todayTotal: 0
    // Bumped after every accrual so bindings over the plain-var containers
    // above re-evaluate.
    property int revision: 0
    property bool dirty: false

    // --- AI agent work time (separate dimension, fed by AgentMonitor) -------
    // Never mixed into the focus numbers above: focus time answers "how long
    // did I look at the screen", these answer "how long were agents working",
    // including while unfocused or locked.
    property real aiUnion: 0     // today, seconds where ≥1 session was working
    property real aiSum: 0       // today, Σ seconds × working sessions
    property int aiPeak: 0       // today, max concurrently working sessions
    // Live sampler state for the UI, not persisted.
    property int aiActiveNow: 0
    property int aiSessionsNow: 0

    // --- focus tracking -----------------------------------------------------
    readonly property string focusedApp: {
        if (GlobalStates.screenLocked) return ""
        const id = ToplevelManager.activeToplevel?.appId ?? ""
        return root.isExcluded(id) ? "" : id
    }
    // The app currently being credited; updated only through accounting
    // events so the interval closed out is always the previous app's.
    property string curApp: ""
    property double lastTick: 0      // ms; last accounting event

    function isExcluded(appId) {
        if (appId === "") return true
        const low = appId.toLowerCase()
        return root.excluded.some(pat => low.includes(pat))
    }

    function dayKeyOf(now) {
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    }

    // Close out the interval since the last accounting event, crediting it to
    // the app that was focused THROUGHOUT that interval (curApp), then arm
    // the next interval with whatever is focused now.
    function accrue() {
        if (!root.ready) return
        const nowMs = Date.now()
        const now = new Date(nowMs)
        const elapsed = (nowMs - root.lastTick) / 1000
        const startHour = new Date(root.lastTick).getHours()
        const nowDayKey = root.dayKeyOf(now)
        const rolledOver = root.curDayKey !== nowDayKey
        root.lastTick = nowMs

        // Day rollover first. The pre-midnight tail of the current interval
        // (≤ one heartbeat, 15s) lands in the new day — accepted inaccuracy.
        if (rolledOver) {
            root.foldToday()
            root.curDayKey = nowDayKey
            root.todayApps = ({})
            root.hours = new Array(24).fill(0)
            root.hoursComplete = true
            root.todayTotal = 0
            root.aiUnion = 0
            root.aiSum = 0
            root.aiPeak = 0
            root.flush() // keys and values travel together; no torn window
        }

        if (root.curApp !== "" && elapsed > 0 && elapsed <= root.idleGapSec) {
            const apps = root.todayApps
            apps[root.curApp] = (apps[root.curApp] ?? 0) + elapsed
            root.todayApps = apps
            const hrs = root.hours
            const creditedHour = rolledOver ? now.getHours() : startHour
            hrs[Math.min(23, Math.max(0, creditedHour))] += elapsed
            root.hours = hrs
            root.todayTotal += elapsed
            root.dirty = true
        }
        root.curApp = root.focusedApp
        root.revision++
    }

    // Close out the window the sampler just measured. Rollover is owned by
    // accrue(); force it here so post-midnight agent seconds land in the new
    // day even if no focus event has fired yet.
    function accrueAi(elapsed, activeCount) {
        if (!root.ready || elapsed <= 0 || activeCount <= 0) return
        if (root.curDayKey !== root.dayKeyOf(new Date())) root.accrue()
        root.aiUnion += elapsed
        root.aiSum += elapsed * activeCount
        if (activeCount > root.aiPeak) root.aiPeak = activeCount
        root.dirty = true
        root.revision++
    }

    // Fold the in-memory day into the daily history: top N apps by seconds,
    // the tail summed into "other".
    function foldToday() {
        if (!root.keepHistory) return
        // Reaching rollover means this tracker observed the day. Preserve a
        // legitimate zero so period averages do not depend on whether the shell
        // happened to restart; days with no tracker record remain unknown.
        if (root.curDayKey === "") return
        root.days = root.trimmedDays(root.days.concat(
            [root.foldedDay(root.curDayKey, root.todayApps,
                            root.hoursComplete ? root.hours : undefined,
                            root.aiUnion, root.aiSum, root.aiPeak)]))
        root.dirty = true
    }

    function foldedDay(key, appsMap, hourValues, aiU, aiS, aiP) {
        const sorted = Object.entries(appsMap)
            .map(([n, s]) => ({ n, s: Math.round(s) }))
            .filter(a => a.s > 0)
            .sort((a, b) => b.s - a.s)
        const top = sorted.slice(0, root.maxAppsPerDay)
        const rest = sorted.slice(root.maxAppsPerDay).reduce((acc, a) => acc + a.s, 0)
        if (rest > 0) top.push({ n: root.otherKey, s: rest })
        const validHours = Array.isArray(hourValues) && hourValues.length === 24
            && hourValues.every(value => typeof value === "number"
                && Number.isFinite(value) && value >= 0)
        const hours = validHours ? hourValues.map(value => Math.round(Number(value))) : undefined
        const folded = { k: key, total: sorted.reduce((acc, a) => acc + a.s, 0), apps: top,
                         aiU: Math.round(aiU ?? 0), aiS: Math.round(aiS ?? 0), aiP: aiP ?? 0 }
        if (hours)
            folded.hours = hours
        return folded
    }

    function trimmedDays(list) {
        return list.sort((a, b) => a.k < b.k ? -1 : a.k > b.k ? 1 : 0)
                   .slice(-root.retentionDays)
    }

    // --- persistence --------------------------------------------------------

    function initFromStore() {
        const now = new Date()
        root.curDayKey = root.dayKeyOf(now)
        let s = null
        try {
            s = JSON.parse(store.histState)
        } catch (e) {
            s = null
        }
        let apps = ({})
        let hrs = new Array(24).fill(0)
        let hrsComplete = true
        let aiU = 0, aiS = 0, aiP = 0
        let past = Array.isArray(s?.days) ? s.days.filter(d => d && typeof d.k === "string") : []
        const day = s?.day
        if (day && typeof day.apps === "object" && day.apps !== null) {
            const dayAi = (day.ai && typeof day.ai === "object") ? day.ai : ({})
            if (day.k === root.curDayKey) {
                apps = day.apps
                const validDayHours = Array.isArray(day.hours) && day.hours.length === 24
                    && day.hours.every(value => typeof value === "number"
                        && Number.isFinite(value) && value >= 0)
                if (validDayHours) {
                    hrs = day.hours.slice()
                    hrsComplete = day.hoursComplete !== false
                } else {
                    hrsComplete = false
                }
                aiU = Number(dayAi.u) || 0
                aiS = Number(dayAi.s) || 0
                aiP = Number(dayAi.p) || 0
            } else if (day.k < root.curDayKey) {
                // The shell was last running on an earlier day: that day is
                // over, fold it into history before starting today from zero.
                past = past.concat([root.foldedDay(day.k, day.apps, day.hours,
                    Number(dayAi.u) || 0, Number(dayAi.s) || 0, Number(dayAi.p) || 0)])
            }
        }
        root.todayApps = apps
        root.aiUnion = aiU
        root.aiSum = aiS
        root.aiPeak = aiP
        root.hours = hrs
        root.hoursComplete = hrsComplete
        root.todayTotal = Object.values(apps).reduce((acc, v) => acc + (Number(v) || 0), 0)
        root.days = root.keepHistory ? root.trimmedDays(past) : []
        root.lastTick = Date.now()
        root.curApp = root.focusedApp
        root.ready = true
        root.revision++
        root.flush() // persist migrations/foldings promptly
    }

    function flush() {
        if (!store || !root.ready) return
        const rounded = ({})
        for (const [n, s] of Object.entries(root.todayApps))
            rounded[n] = Math.round(s)
        store.histState = JSON.stringify({
            v: 1,
            day: { k: root.curDayKey, apps: rounded, hours: root.hours.map(v => Math.round(v)),
                   hoursComplete: root.hoursComplete,
                   ai: { u: Math.round(root.aiUnion), s: Math.round(root.aiSum), p: root.aiPeak } },
            days: root.keepHistory ? root.days : []
        })
        root.dirty = false
    }

    // --- events -------------------------------------------------------------

    onFocusedAppChanged: {
        // Covers focus switches, lock/unlock, and exclusion-list edits: the
        // interval that just ended is credited to the app it belonged to.
        if (root.ready) root.accrue()
    }

    onStoreReadyChanged: {
        if (root.storeReady && !root.ready) root.initFromStore()
    }

    onKeepHistoryChanged: {
        if (root.ready && !root.keepHistory && root.days.length > 0) {
            root.days = []
            root.flush()
        }
    }

    // Heartbeat: bounds the interval length so suspend gaps are detected and
    // long single-app sessions accrue steadily. Accounting, not display.
    Timer {
        interval: 15000
        running: root.ready
        repeat: true
        onTriggered: root.accrue()
    }

    // Flush at most once a minute: every JsonAdapter assignment is a config
    // file write.
    Timer {
        interval: 60000
        running: root.ready
        repeat: true
        onTriggered: if (root.dirty) root.flush()
    }

    Component.onDestruction: {
        if (root.ready) {
            root.accrue()
            root.flush()
        }
    }

    // --- helpers for consumers ---------------------------------------------

    function ranking(limit) {
        return Object.entries(root.todayApps)
            .map(([n, s]) => ({ n, s }))
            .filter(a => a.s >= 1)
            .sort((a, b) => b.s - a.s)
            .slice(0, limit)
    }

    // Last 7 calendar days ending today: zero-filled for days with no record.
    function trend7() {
        const out = []
        const now = new Date()
        for (let i = 6; i >= 0; i--) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
            const k = root.dayKeyOf(d)
            if (i === 0) {
                out.push({ k, total: root.todayTotal, ai: root.aiUnion, dow: d.getDay(), isToday: true })
            } else {
                const rec = root.days.find(x => x.k === k)
                out.push({ k, total: rec?.total ?? 0, ai: Number(rec?.aiU) || 0, dow: d.getDay(), isToday: false })
            }
        }
        return out
    }

    // Last 30 calendar days ending today. Missing historical records stay
    // null so charts can distinguish unknown coverage from a recorded zero.
    function trend30() {
        const out = []
        const now = new Date()
        for (let i = 29; i >= 0; i--) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
            const k = root.dayKeyOf(d)
            if (i === 0) {
                out.push({ k, total: root.todayTotal })
            } else {
                const rec = root.days.find(x => x.k === k)
                const total = rec?.total
                out.push({ k, total: typeof total === "number"
                    && Number.isFinite(total) && total >= 0 ? total : null })
            }
        }
        return out
    }
}
