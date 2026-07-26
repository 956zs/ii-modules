import QtQuick
import Quickshell.Io

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

    // Sentinel for pruned long-tail apps; translated at display time.
    readonly property string otherKey: "__other"
    readonly property int maxTrackedApps: 30

    onActiveChanged: {
        if (active) {
            source = "starting"
            nethogsBatch = []
            nethogsSawSnapshot = false
            lastCum = {}
            lastBatchTime = 0
            nethogs.running = true
            startupTimeout.restart()
        } else {
            nethogs.running = false
            ssTimer.stop()
            ssProc.running = false
            apps = []
            ssPrevious = null
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

    function tryInitAcct() {
        if (acctLoaded || !store || !storeReady || bootId === "") return
        let s = null
        try {
            s = JSON.parse(store.appAcctState)
        } catch (e) {
            s = null
        }
        const map = {}
        for (const e of (s?.apps ?? [])) {
            map[e.n] = { dk: e.dk, drx: e.drx, dtx: e.dtx,
                         mk: e.mk, mrx: Math.max(e.mrx, e.drx), mtx: Math.max(e.mtx, e.dtx),
                         brx: e.brx, btx: e.btx }
        }
        if ((s?.bootId ?? "") !== bootId) {
            for (const n in map) {
                map[n].brx = 0
                map[n].btx = 0
            }
        }
        acct = map
        acctLoaded = true
        acctRevision++
        flushAcct() // persist the boot reset / repairs promptly
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
        const rows = []
        for (const n in acct) {
            const a = acct[n]
            const rx = period === "today" ? a.drx : period === "month" ? a.mrx : a.brx
            const tx = period === "today" ? a.dtx : period === "month" ? a.mtx : a.btx
            if (rx + tx > 0) rows.push({ name: n, rx, tx })
        }
        return rows.sort((x, y) => (y.rx + y.tx) - (x.rx + x.tx))
    }

    function flushAcct() {
        if (!store || !acctLoaded) return
        // Prune the long tail so the config file stays bounded: keep the top
        // N by month volume, fold the rest into a single "other" bucket.
        const names = Object.keys(acct)
            .filter(n => n !== otherKey)
            .sort((x, y) => (acct[y].mrx + acct[y].mtx) - (acct[x].mrx + acct[x].mtx))
        if (names.length > maxTrackedApps) {
            const now = new Date()
            const other = acct[otherKey] ?? { dk: dayKey(now), drx: 0, dtx: 0,
                                              mk: monthKey(now), mrx: 0, mtx: 0, brx: 0, btx: 0 }
            for (const n of names.slice(maxTrackedApps)) {
                const a = acct[n]
                other.drx += a.drx; other.dtx += a.dtx
                other.mrx += a.mrx; other.mtx += a.mtx
                other.brx += a.brx; other.btx += a.btx
                delete acct[n]
            }
            acct[otherKey] = other
        }
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
        running: root.active && root.acctLoaded
        repeat: true
        onTriggered: root.flushAcct()
    }

    Component.onDestruction: flushAcct()

    // --- name prettifying --------------------------------------------------

    property var commByPid: ({})
    // entryId -> {pid, rx, tx}: deltas held back until the name resolves, so
    // Electron apps reporting /proc/self/exe aren't misfiled under "exe".
    property var pendingDelta: ({})

    function prettyName(cmdline, pid) {
        const exe = cmdline.split(" ")[0]
        const base = exe.substring(exe.lastIndexOf("/") + 1)
        if (base === "exe" || base === "") {
            return root.commByPid[pid] ?? null // null -> needs ps resolution
        }
        return base
    }

    Process {
        id: psProc
        property list<string> pending: []
        command: ["ps", "-o", "pid=", "-o", "comm=", "-p", pending.join(",")]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = Object.assign({}, root.commByPid)
                for (const line of text.split("\n")) {
                    const m = line.trim().match(/^(\d+)\s+(.+)$/)
                    if (m) map[m[1]] = m[2]
                }
                root.commByPid = map
            }
        }
    }

    function resolveComms(pids) {
        const unknown = pids.filter(p => !(p in root.commByPid))
        if (unknown.length === 0 || psProc.running) return
        psProc.pending = unknown
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
            if (!root.nethogsSawSnapshot) {
                nethogs.running = false
                root.startSsFallback()
            }
        }
    }

    Process {
        id: nethogs
        // -v 2: cumulative bytes since nethogs start — deltas survive UI
        // pauses, unlike the KB/s view. nethogs block-buffers stdout when
        // piped; stdbuf keeps it line-based.
        command: ["stdbuf", "-oL", "nethogs", "-t", "-v", "2", "-d", String(root.nethogsSeconds)]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.startsWith("Refreshing:")) {
                    root.commitNethogsBatch()
                    return
                }
                // "<prog>/<pid>/<uid>\t<sent bytes>\t<recv bytes>"
                const parts = line.split("\t")
                if (parts.length < 3) return
                const tx = parseFloat(parts[parts.length - 2])
                const rx = parseFloat(parts[parts.length - 1])
                const idPart = parts.slice(0, parts.length - 2).join("\t")
                const m = idPart.match(/^(.*)\/(\d+)\/(\d+)$/)
                if (!m || m[2] === "0" || isNaN(tx) || isNaN(rx)) return
                root.nethogsBatch.push({ cmdline: m[1], pid: m[2], rx, tx })
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.active && root.source !== "ss") {
                root.startSsFallback()
            }
        }
    }

    function commitNethogsBatch() {
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

        const rates = {}
        const unresolved = []
        for (const e of batch) {
            const entryId = `${e.cmdline}/${e.pid}`
            const prev = root.lastCum[entryId]
            root.lastCum[entryId] = { rx: e.rx, tx: e.tx }
            // First sighting or counter shrink (restart): baseline only.
            if (!prev || e.rx < prev.rx || e.tx < prev.tx) continue
            const drx = e.rx - prev.rx
            const dtx = e.tx - prev.tx
            if (drx === 0 && dtx === 0) continue

            const name = root.prettyName(e.cmdline, e.pid)
            if (name === null) {
                // Park the delta until ps tells us the real name.
                const p = root.pendingDelta[entryId] ?? { pid: e.pid, rx: 0, tx: 0 }
                p.rx += drx
                p.tx += dtx
                root.pendingDelta[entryId] = p
                unresolved.push(e.pid)
                continue
            }
            root.accumulate(name, drx, dtx)
            if (elapsed > 0) {
                rates[name] = rates[name] ?? { name, down: 0, up: 0 }
                rates[name].down += drx / elapsed
                rates[name].up += dtx / elapsed
            }
        }

        // Drain parked deltas whose names have resolved since.
        for (const entryId in root.pendingDelta) {
            const p = root.pendingDelta[entryId]
            const name = root.commByPid[p.pid]
            if (name !== undefined) {
                root.accumulate(name, p.rx, p.tx)
                delete root.pendingDelta[entryId]
            }
        }
        if (unresolved.length > 0) root.resolveComms(unresolved)

        root.apps = Object.values(rates)
            .filter(a => a.down + a.up >= 1)
            .sort((a, b) => (b.down + b.up) - (a.down + a.up))
        root.acctRevision++
    }

    // --- ss fallback (TCP only) --------------------------------------------

    property var ssPrevious: null

    function startSsFallback() {
        root.source = "ss"
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
            onStreamFinished: root.commitSsSample(text)
        }
        onExited: (exitCode, exitStatus) => {
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
