import QtQuick
import Quickshell.Io

/*
 * Per-app bandwidth sampler (instance, not a singleton). Runs only while
 * `active` (the popup binds it to its own lifetime, so nothing is spawned
 * when the popup is closed).
 *
 * Primary source: `nethogs -t` (pcap; sees TCP and UDP, so QUIC-heavy apps
 * like browsers are counted). Declared in requires.system; running it
 * unprivileged needs file capabilities on the binary (see README). If it
 * dies or stays silent — no caps, other distro, whatever — we degrade to
 * polling `ss -tinp`, which is unprivileged but kernel-TCP only.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool active: false
    property int updateInterval: 2000

    // "starting" | "nethogs" | "ss" | "none"
    property string source: "starting"
    readonly property bool tcpOnly: source === "ss"
    // [{name, down, up}] bytes/s, sorted by down+up descending.
    property list<var> apps: []
    readonly property var topApp: apps.length > 0 ? apps[0] : null
    // Share of the total sampled traffic attributed to the top app, 0..1.
    readonly property real topShare: {
        if (!topApp) return 0
        let total = 0
        for (const a of apps) total += a.down + a.up
        return total > 0 ? (topApp.down + topApp.up) / total : 0
    }

    readonly property int nethogsSeconds: Math.max(1, Math.round(updateInterval / 1000))

    onActiveChanged: {
        if (active) {
            source = "starting"
            nethogsBatch = []
            nethogsSawSnapshot = false
            nethogs.running = true
            startupTimeout.restart()
        } else {
            nethogs.running = false
            ssTimer.stop()
            ssProc.running = false
            apps = []
            ssPrevious = null
        }
    }

    // --- name prettifying --------------------------------------------------

    property var commByPid: ({})

    function prettyName(cmdline, pid) {
        // nethogs prints "<cmdline>/<pid>/<uid>"; cmdline itself may hold
        // spaces and arguments. First token, basename of it.
        const exe = cmdline.split(" ")[0]
        const base = exe.substring(exe.lastIndexOf("/") + 1)
        // Electron apps often resolve to /proc/self/exe; fall back to comm.
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
        // nethogs block-buffers stdout when piped; stdbuf keeps it line-based.
        command: ["stdbuf", "-oL", "nethogs", "-t", "-d", String(root.nethogsSeconds)]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                if (line.startsWith("Refreshing:")) {
                    root.commitNethogsBatch()
                    return
                }
                // "<prog>/<pid>/<uid>\t<sentKB/s>\t<recvKB/s>"
                const parts = line.split("\t")
                if (parts.length < 3) return
                const up = parseFloat(parts[parts.length - 2])
                const down = parseFloat(parts[parts.length - 1])
                const idPart = parts.slice(0, parts.length - 2).join("\t")
                const m = idPart.match(/^(.*)\/(\d+)\/(\d+)$/)
                if (!m || m[2] === "0" || isNaN(up) || isNaN(down)) return
                root.nethogsBatch.push({ cmdline: m[1], pid: m[2], up: up * 1024, down: down * 1024 })
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
        const byName = {}
        const unresolved = []
        for (const e of batch) {
            const name = root.prettyName(e.cmdline, e.pid)
            if (name === null) {
                unresolved.push(e.pid)
                continue
            }
            byName[name] = byName[name] ?? { name, down: 0, up: 0 }
            byName[name].down += e.down
            byName[name].up += e.up
        }
        if (unresolved.length > 0) root.resolveComms(unresolved)
        root.apps = Object.values(byName)
            .filter(a => a.down + a.up >= 1)
            .sort((a, b) => (b.down + b.up) - (a.down + a.up))
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
        // give rates. Sockets vanish when closed; per-app sums can therefore
        // shrink, so negative deltas are clamped.
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
            const down = Math.max(0, totals[n].rx - p.rx) / elapsed
            const up = Math.max(0, totals[n].tx - p.tx) / elapsed
            if (down + up >= 1) out.push({ name: n, down, up })
        }
        root.apps = out.sort((a, b) => (b.down + b.up) - (a.down + a.up))
    }
}
