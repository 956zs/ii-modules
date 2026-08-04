import QtQuick
import Quickshell.Io
import "AppTrafficLogic.js" as AppTrafficLogic

/*
 * Per-app traffic sampler and accountant (instance, not a singleton).
 *
 * Runs for the whole life of the bar widget (not just while the popup is
 * open): per-app history only exists if someone is watching, so the sampler
 * accumulates boot/today/month totals per app and persists them through the
 * ConfigLoader adapter. A userspace sampler can only account for time it was
 * actually running — the seconds between system boot and shell start are lost,
 * for nethogs and ss alike.
 *
 * Primary source: `nethogs -t -v 2` (pcap, cumulative bytes since process
 * start; sees TCP and UDP, so QUIC-heavy apps like browsers are counted).
 * Declared in requires.system; rootless capture needs file capabilities on
 * the binary (see README). If it dies or stays silent, degrade to polling
 * `ss -tinp` — unprivileged but kernel-TCP only.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool active: false
    property int updateInterval: 2000
    // ConfigLoader adapter + its ready flag, for persisted accounting.
    property var store: null
    property bool storeReady: false
    property bool writer: true

    // "starting" | "nethogs" | "ss" | "none"
    property string source: "starting"
    readonly property bool tcpOnly: source === "ss"
    // Live rates, [{name, down, up}] bytes/s sorted by down+up descending.
    property list<var> apps: []
    // Bumped whenever accounting changes so bindings can recompute ranking().
    property int acctRevision: 0

    readonly property int nethogsSeconds: Math.max(1, Math.round(updateInterval / 1000))

    // name -> {dk, drx, dtx, mk, mrx, mtx, brx, btx}  (bytes; d=day m=month b=boot)
    property var acct: ({})
    property bool acctLoaded: false
    property string bootId: ""
    property int monitoringGeneration: 0
    property int psQuerySerial: 0
    property bool psStopping: false
    property bool nethogsStopping: false
    property bool fallbackPending: false
    property bool ssStopping: false

    // Sentinel for pruned long-tail apps; translated at display time.
    readonly property string otherKey: "__other"
    readonly property string unattributedProcessKey: "__unattributed_process"
    readonly property int maxTrackedApps: 30

    onActiveChanged: {
        monitoringGeneration++
        psQuerySerial++
        psStopping = psProc.running
        psProc.running = false
        psProc.pending = []
        psQueue = []
        if (active) {
            source = "starting"
            nethogsBatch = []
            nethogsSawSnapshot = false
            lastCum = {}
            commByPid = {}
            pendingDelta = {}
            psQueue = []
            lastBatchTime = 0
            ssTimer.stop()
            ssStopping = ssStopping || ssProc.running
            ssProc.running = false
            if (!ssStopping && !nethogsStopping)
                startNethogs()
        } else {
            startupTimeout.stop()
            fallbackPending = false
            finalizePendingAccounting()
            nethogsStopping = nethogsStopping || nethogs.running
            nethogs.running = false
            ssTimer.stop()
            ssStopping = ssStopping || ssProc.running
            ssProc.running = false
            apps = []
            ssPrevious = null
            lastCum = {}
            commByPid = {}
            pendingDelta = {}
            psQueue = []
            flushAcct()
        }
    }

    // --- persisted accounting --------------------------------------------

    FileView {
        id: bootIdFile
        path: "/proc/sys/kernel/random/boot_id"
        onLoaded: {
            root.bootId = text().trim()
            root.tryInitAcct()
        }
    }

    onStoreReadyChanged: tryInitAcct()
    onWriterChanged: {
        source = writer ? "starting" : "stored"
        if (writer && acctLoaded && storeReady) loadAccounting()
        tryInitAcct()
    }

    Connections {
        target: root.store
        ignoreUnknownSignals: true
        function onAppAcctStateChanged() {
            if (!root.writer && root.acctLoaded && root.storeReady) root.loadAccounting()
        }
    }

    function loadAccounting() {
        acct = AppTrafficLogic.restoreAccounting(store?.appAcctState ?? "", bootId, new Date())
        acctRevision++
    }

    function tryInitAcct() {
        if (acctLoaded || !store || !storeReady || bootId === "") return
        loadAccounting()
        acctLoaded = true
        if (writer) flushAcct() // persist the boot reset / repairs promptly
    }

    function dayKey(now) {
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    }

    function monthKey(now) {
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`
    }

    function accumulate(name, drx, dtx) {
        if (!acctLoaded || (drx <= 0 && dtx <= 0)) return
        const now = new Date()
        const dk = dayKey(now)
        const mk = monthKey(now)
        const a = acct[name] ?? { dk, drx: 0, dtx: 0, mk, mrx: 0, mtx: 0, brx: 0, btx: 0 }
        if (a.dk !== dk) { a.dk = dk; a.drx = 0; a.dtx = 0 }
        if (a.mk !== mk) { a.mk = mk; a.mrx = 0; a.mtx = 0 }
        a.drx += drx; a.dtx += dtx
        a.mrx += drx; a.mtx += dtx
        a.brx += drx; a.btx += dtx
        // A month contains its days — self-heal any impossible stored state.
        a.mrx = Math.max(a.mrx, a.drx)
        a.mtx = Math.max(a.mtx, a.dtx)
        acct[name] = a
    }

    // Ranking for a period: [{name, rx, tx}] sorted by rx+tx descending.
    // Callers reference acctRevision in the binding for reactivity.
    function ranking(period) {
        return AppTrafficLogic.ranking(acct, period, new Date())
    }

    function finalizePendingAccounting() {
        const finalized = AppTrafficLogic.finalizePending(
            root.pendingDelta, root.commByPid, root.unattributedProcessKey)
        root.pendingDelta = finalized.pendingDelta
        for (const app of finalized.accounting)
            root.accumulate(app.name, app.rx, app.tx)
        if (finalized.accounting.length > 0)
            root.acctRevision++
    }

    function flushAcct() {
        if (!writer || !store || !acctLoaded) return
        acct = AppTrafficLogic.pruneAccounting(acct, otherKey, maxTrackedApps, new Date())
        const out = []
        for (const n in acct) {
            const a = acct[n]
            out.push({ n, dk: a.dk, drx: a.drx, dtx: a.dtx,
                       mk: a.mk, mrx: a.mrx, mtx: a.mtx, brx: a.brx, btx: a.btx })
        }
        // One blob, one assignment, one consistent write.
        store.appAcctState = JSON.stringify({ v: 1, bootId, apps: out })
    }

    // Each JsonAdapter assignment is a config-file write; flush sparsely.
    Timer {
        interval: 60000
        running: root.writer && root.active && root.acctLoaded
        repeat: true
        onTriggered: root.flushAcct()
    }

    Component.onDestruction: {
        finalizePendingAccounting()
        flushAcct()
    }

    // --- name prettifying --------------------------------------------------

    property var commByPid: ({})
    property var psQueue: []
    // entryId -> {pid, rx, tx}: deltas held back until the name resolves, so
    // Electron apps reporting /proc/self/exe aren't misfiled under "exe".
    property var pendingDelta: ({})

    Process {
        id: psProc
        property list<string> pending: []
        property list<string> pendingEntryIds: []
        property int generation: -1
        property int querySerial: -1
        command: ["ps", "-o", "pid=", "-o", "comm=", "-p", pending.join(",")]
        stdout: StdioCollector {
            onStreamFinished: {
                if (psProc.generation !== root.monitoringGeneration
                        || psProc.querySerial !== root.psQuerySerial) return
                const map = Object.assign({}, root.commByPid)
                for (const line of text.split("\n")) {
                    const m = line.trim().match(/^(\d+)\s+(.+)$/)
                    if (m && psProc.pending.includes(m[1])) map[m[1]] = m[2]
                }
                const drained = AppTrafficLogic.drainResolvedPending(
                    root.pendingDelta, map, Object.keys(root.lastCum).map(entryId => entryId.substring(entryId.lastIndexOf("/") + 1)))
                root.commByPid = drained.commByPid
                root.pendingDelta = drained.pendingDelta
                for (const app of drained.accounting) root.accumulate(app.name, app.rx, app.tx)
                if (drained.accounting.length > 0) root.acctRevision++
            }
        }
        onExited: {
            root.psStopping = false
            if (psProc.generation === root.monitoringGeneration)
                root.resolveComms(root.psQueue)
        }
    }

    function resolveComms(pids) {
        const unknown = [...new Set(pids.map(pid => String(pid)))]
            .filter(pid => !(pid in root.commByPid))
        root.psQueue = unknown
        if (unknown.length === 0 || psProc.running || root.psStopping) return
        psProc.pending = unknown
        psProc.pendingEntryIds = Object.keys(root.pendingDelta)
            .filter(entryId => unknown.includes(String(root.pendingDelta[entryId].pid)))
        psProc.generation = root.monitoringGeneration
        psProc.querySerial = ++root.psQuerySerial
        root.psQueue = []
        psProc.running = true
    }

    // --- nethogs (primary) -------------------------------------------------

    property var nethogsBatch: []
    property bool nethogsSawSnapshot: false
    // entryId -> {rx, tx}: last cumulative reading, for deltas. In-memory
    // only; a nethogs restart resets its counters, so baselines restart too.
    property var lastCum: ({})
    property real lastBatchTime: 0

    // If nethogs produced nothing usable in time (missing caps, pcap refused),
    // fall back. Its "cannot open netlink/pcap" chatter goes to stderr, so
    // silence on stdout is the reliable signal.
    Timer {
        id: startupTimeout
        interval: root.updateInterval * 2 + 4000
        onTriggered: {
            if (!root.active) return;
            if (!root.nethogsSawSnapshot)
                root.startSsFallback()
        }
    }

    function startNethogs() {
        if (!root.active || root.nethogsStopping || root.ssStopping)
            return
        root.source = "starting"
        root.nethogsBatch = []
        root.nethogsSawSnapshot = false
        nethogs.running = true
        startupTimeout.restart()
    }

    Process {
        id: nethogs
        // -C captures TCP and UDP; without it QUIC-heavy apps are absent from
        // per-app totals. -v 2 emits cumulative bytes, so deltas survive UI
        // pauses. nethogs block-buffers stdout when piped; stdbuf keeps it
        // line-based.
        command: AppTrafficLogic.nethogsCommand(root.nethogsSeconds)
        stdout: SplitParser {
            onRead: data => {
                if (!root.active || root.source === "ss") return;
                const parsed = AppTrafficLogic.parseNethogsLine(data)
                if (!parsed) return
                if (parsed.refresh) {
                    root.commitNethogsBatch()
                    return
                }
                root.nethogsBatch.push(parsed)
            }
        }
        onExited: (exitCode, exitStatus) => {
            const requestedStop = root.nethogsStopping
            root.nethogsStopping = false
            startupTimeout.stop()
            if (!root.active)
                return
            if (root.fallbackPending) {
                root.fallbackPending = false
                root.startSsFallback()
            } else if (requestedStop && root.source === "starting" && !root.ssStopping) {
                root.startNethogs()
            } else {
                root.startSsFallback()
            }
        }
    }

    function commitNethogsBatch() {
        if (!root.active || root.source === "ss")
            return
        const batch = root.nethogsBatch
        root.nethogsBatch = []
        if (!root.nethogsSawSnapshot) {
            root.nethogsSawSnapshot = true
            root.source = "nethogs"
            startupTimeout.stop()
        }

        const now = Date.now()
        const elapsed = root.lastBatchTime > 0 ? (now - root.lastBatchTime) / 1000 : 0
        root.lastBatchTime = now

        const result = AppTrafficLogic.commitNethogsBatch(
            batch, root.lastCum, elapsed, root.commByPid, root.pendingDelta)
        root.lastCum = result.lastCum
        root.commByPid = result.commByPid
        root.pendingDelta = result.pendingDelta
        const queryStillActive = psProc.pendingEntryIds.every(
            entryId => result.activeEntryIds.includes(entryId))
        if (psProc.running && !queryStillActive) {
            root.psQuerySerial++
            root.psStopping = true
            psProc.running = false
        }
        for (const app of result.accounting) root.accumulate(app.name, app.rx, app.tx)
        if (result.unresolvedPids.length > 0) root.resolveComms(result.unresolvedPids)
        root.apps = result.rates
        root.acctRevision++
    }

    // --- ss fallback (TCP only) --------------------------------------------

    property var ssPrevious: null

    function startSsFallback() {
        if (!root.active) return
        startupTimeout.stop()
        root.source = "ss"
        if (nethogs.running || root.nethogsStopping) {
            root.fallbackPending = true
            root.nethogsStopping = true
            nethogs.running = false
            return
        }
        if (root.ssStopping)
            return
        root.fallbackPending = false
        root.ssPrevious = null
        ssTimer.start()
        ssProc.running = true
    }

    Timer {
        id: ssTimer
        interval: root.updateInterval
        repeat: true
        onTriggered: if (!ssProc.running) ssProc.running = true
    }

    Process {
        id: ssProc
        command: ["ss", "-tinpH"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.active && root.source === "ss")
                    root.commitSsSample(text)
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.ssStopping = false
            if (!root.active)
                return
            if (root.source === "starting") {
                root.startNethogs()
                return
            }
            if (exitCode !== 0) {
                ssTimer.stop()
                root.source = "none"
                root.apps = []
            }
        }
    }

    function commitSsSample(text) {
        // Per-socket cumulative bytes, summed per process name. Two samples
        // give deltas. Sockets vanish when closed; per-app sums can therefore
        // shrink, so negative deltas are clamped — traffic on sockets that
        // opened and closed between polls is lost (pcap has no such gap).
        const now = Date.now()
        const totals = {}
        let name = null
        for (const line of text.split("\n")) {
            const pm = line.match(/users:\(\("([^"]+)",pid=\d+/)
            if (pm) {
                name = pm[1]
                continue
            }
            if (name === null) continue
            const rx = line.match(/bytes_received:(\d+)/)
            const tx = line.match(/bytes_sent:(\d+)/)
            if (rx || tx) {
                totals[name] = totals[name] ?? { rx: 0, tx: 0 }
                totals[name].rx += rx ? parseInt(rx[1]) : 0
                totals[name].tx += tx ? parseInt(tx[1]) : 0
                name = null
            }
        }
        const prev = root.ssPrevious
        root.ssPrevious = { time: now, totals }
        if (!prev || now <= prev.time) return
        const elapsed = (now - prev.time) / 1000
        const out = []
        for (const n in totals) {
            const p = prev.totals[n] ?? { rx: 0, tx: 0 }
            const drx = Math.max(0, totals[n].rx - p.rx)
            const dtx = Math.max(0, totals[n].tx - p.tx)
            if (drx + dtx === 0) continue
            root.accumulate(n, drx, dtx)
            const down = drx / elapsed
            const up = dtx / elapsed
            if (down + up >= 1) out.push({ name: n, down, up })
        }
        root.apps = out.sort((a, b) => (b.down + b.up) - (a.down + a.up))
        root.acctRevision++
    }
}
