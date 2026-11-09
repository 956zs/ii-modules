function dayKey(now) {
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
}

function monthKey(now) {
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`
}

function bytes(value) {
    return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : 0
}

function migrateStatsPeriod(serialized, statsPeriod, statsPeriodSchema) {
    let stored = null
    try {
        stored = JSON.parse(serialized)
    } catch (error) {
        stored = null
    }

    const storedPeriod = typeof stored?.statsPeriod === "string" ? stored.statsPeriod : statsPeriod
    const hasStoredSchema = stored !== null
        && typeof stored === "object"
        && Object.prototype.hasOwnProperty.call(stored, "statsPeriodSchema")
    const schemaValue = hasStoredSchema ? stored.statsPeriodSchema : 0
    const schema = Number.isInteger(schemaValue) && schemaValue >= 0 ? schemaValue : 0
    if (schema > 1) {
        return { statsPeriod: storedPeriod, statsPeriodSchema: schema }
    }

    const period = storedPeriod === "boot" || storedPeriod === "month" ? storedPeriod : "today"
    if (schema < 1) {
        return {
            statsPeriod: period === "boot" ? "today" : period,
            statsPeriodSchema: 1
        }
    }
    return { statsPeriod: period, statsPeriodSchema: schema }
}

const APP_ACCT_SCHEMA = 2

function appAccountingSchema() {
    return APP_ACCT_SCHEMA
}

function restoreAccounting(serialized, bootId, now) {
    let state = null
    try {
        state = JSON.parse(serialized)
    } catch (error) {
        state = null
    }

    const currentDay = dayKey(now)
    const currentMonth = monthKey(now)
    // Schema 1 (before 1.8.0) baselined every newly seen process and lost its
    // first sampling interval, undercounting per-app totals by up to half.
    // Those totals cannot be repaired, so they are discarded, not mixed in.
    const entries = state?.v === APP_ACCT_SCHEMA && Array.isArray(state?.apps) ? state.apps : []
    const map = {}
    for (const entry of entries) {
        if (!entry || typeof entry.n !== "string" || entry.n === "") continue
        const sameDay = entry.dk === currentDay
        const sameMonth = entry.mk === currentMonth
        const dayRx = sameDay ? bytes(entry.drx) : 0
        const dayTx = sameDay ? bytes(entry.dtx) : 0
        const monthContainsDay = sameDay && currentDay.startsWith(currentMonth)
        map[entry.n] = {
            dk: currentDay,
            drx: dayRx,
            dtx: dayTx,
            mk: currentMonth,
            mrx: sameMonth || monthContainsDay ? Math.max(sameMonth ? bytes(entry.mrx) : 0, dayRx) : 0,
            mtx: sameMonth || monthContainsDay ? Math.max(sameMonth ? bytes(entry.mtx) : 0, dayTx) : 0,
            brx: bytes(entry.brx),
            btx: bytes(entry.btx)
        }
    }
    if ((state?.bootId ?? "") !== bootId) {
        for (const name in map) {
            map[name].brx = 0
            map[name].btx = 0
        }
    }
    return map
}

function ranking(acct, period, now) {
    const currentDay = dayKey(now)
    const currentMonth = monthKey(now)
    const rows = []
    for (const name in (acct ?? {})) {
        const entry = acct[name]
        const rx = period === "today" ? (entry.dk === currentDay ? bytes(entry.drx) : 0)
            : period === "month" ? (entry.mk === currentMonth ? bytes(entry.mrx) : 0)
            : bytes(entry.brx)
        const tx = period === "today" ? (entry.dk === currentDay ? bytes(entry.dtx) : 0)
            : period === "month" ? (entry.mk === currentMonth ? bytes(entry.mtx) : 0)
            : bytes(entry.btx)
        if (rx + tx > 0) rows.push({ name, rx, tx })
    }
    return rows.sort((left, right) => (right.rx + right.tx) - (left.rx + left.tx))
}

function pruneAccounting(acct, otherKey, maxTrackedApps, now) {
    const currentDay = dayKey(now)
    const currentMonth = monthKey(now)
    const next = {}
    for (const name in (acct ?? {})) {
        const entry = acct[name] ?? {}
        const sameDay = entry.dk === currentDay
        const sameMonth = entry.mk === currentMonth
        next[name] = {
            dk: currentDay,
            drx: sameDay ? bytes(entry.drx) : 0,
            dtx: sameDay ? bytes(entry.dtx) : 0,
            mk: currentMonth,
            mrx: sameMonth ? bytes(entry.mrx) : 0,
            mtx: sameMonth ? bytes(entry.mtx) : 0,
            brx: bytes(entry.brx),
            btx: bytes(entry.btx)
        }
    }

    const names = Object.keys(next)
        .filter(name => name !== otherKey && !name.startsWith("__unattributed_"))
        .sort((left, right) => (next[right].mrx + next[right].mtx)
            - (next[left].mrx + next[left].mtx))
    if (names.length <= maxTrackedApps) return next

    const other = next[otherKey] ?? {
        dk: currentDay, drx: 0, dtx: 0,
        mk: currentMonth, mrx: 0, mtx: 0,
        brx: 0, btx: 0
    }
    for (const name of names.slice(maxTrackedApps)) {
        const entry = next[name]
        other.drx += entry.drx
        other.dtx += entry.dtx
        other.mrx += entry.mrx
        other.mtx += entry.mtx
        other.brx += entry.brx
        other.btx += entry.btx
        delete next[name]
    }
    next[otherKey] = other
    return next
}

// Settles parked bytes after a ps name query. Resolved PIDs are credited to
// their name; PIDs the query asked about but ps no longer knows have exited,
// so their bytes go to the collector-provided fallback (pktz comm) or the
// unattributed-process bucket. Other parked bytes wait for a later query.
function drainResolvedPending(pendingDelta, commByPid, queriedPids, unattributedKey) {
    const fallbackKey = typeof unattributedKey === "string" && unattributedKey !== ""
        ? unattributedKey : "__unattributed_process"
    const queried = new Set(Array.from(queriedPids ?? [], pid => String(pid)))
    const nextPending = {}
    const accounting = {}
    for (const entryId in (pendingDelta ?? {})) {
        const parked = pendingDelta[entryId]
        if (!parked || typeof parked !== "object") continue
        const pid = String(parked.pid)
        const name = commByPid?.[pid]
        if (typeof name === "string" && name !== "") {
            addTraffic(accounting, name, bytes(parked.rx), bytes(parked.tx))
        } else if (queried.has(pid)) {
            addTraffic(accounting, parked.fallback || fallbackKey, bytes(parked.rx), bytes(parked.tx))
        } else {
            nextPending[entryId] = Object.assign({}, parked)
        }
    }
    return {
        pendingDelta: nextPending,
        accounting: Object.values(accounting)
    }
}

function finalizePending(pendingDelta, commByPid, unattributedKey) {
    const accounting = {}
    const fallback = typeof unattributedKey === "string" && unattributedKey !== ""
        ? unattributedKey : "__unattributed_process"
    for (const entryId in (pendingDelta ?? {})) {
        const parked = pendingDelta[entryId]
        if (!parked || typeof parked !== "object") continue
        const rx = bytes(parked.rx)
        const tx = bytes(parked.tx)
        if (rx + tx === 0) continue
        const resolved = commByPid?.[String(parked.pid)]
        const name = typeof resolved === "string" && resolved !== "" ? resolved
            : typeof parked.fallback === "string" && parked.fallback !== "" ? parked.fallback : fallback
        addTraffic(accounting, name, rx, tx)
    }
    return { pendingDelta: {}, accounting: Object.values(accounting) }
}

function pktzTimestampMs(value) {
    if (typeof value !== "string") return -1
    const match = value.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$/)
    if (!match) return -1
    const milliseconds = (match[2] ?? "").padEnd(3, "0").substring(0, 3)
    const parsed = Date.parse(`${match[1]}.${milliseconds}Z`)
    return Number.isFinite(parsed) ? parsed : -1
}

function pktzCandidates(home) {
    const candidates = ["pktz"]
    if (typeof home !== "string" || home === "") return candidates
    candidates.push(`${home}/go/bin/pktz`)
    candidates.push(`${home}/.local/bin/pktz`)
    return candidates
}

function pktzCommand(executable) {
    const binary = typeof executable === "string" && executable !== "" ? executable : "pktz"
    return [binary, "--log"]
}

// The whole-system meter excludes loopback and overlay interfaces, so per-app
// sources must too or they stop reconciling with it: localhost proxy chains
// (adb→scrcpy, local API proxies) otherwise count every relayed byte once per
// leg, and traffic inside a tailscale tunnel counts once as the inner flow and
// again as tailscaled's encrypted wire bytes.
function excludedTrafficEndpoint(ip) {
    if (typeof ip !== "string" || ip === "") return false
    let addr = ip.toLowerCase()
    if (addr.startsWith("::ffff:")) addr = addr.substring(7)
    if (addr === "::1" || addr.startsWith("127.")) return true
    if (addr.startsWith("fd7a:115c:a1e0")) return true
    const cgnat = addr.match(/^100\.(\d{1,3})\./)
    if (cgnat) {
        const octet = Number(cgnat[1])
        if (octet >= 64 && octet <= 127) return true
    }
    return false
}

function parsePktzLine(data) {
    if (typeof data !== "string" || data.trim() === "") return null

    let record
    try {
        record = JSON.parse(data)
    } catch (error) {
        return null
    }
    if (record === null || typeof record !== "object") return null
    if (record.type !== "process" && record.type !== "conn") return null
    if (typeof record.ts !== "string" || pktzTimestampMs(record.ts) < 0)
        return null
    if (!Number.isSafeInteger(record.pid) || record.pid <= 0) return null
    if (typeof record.comm !== "string" || record.comm === "") return null
    if (!Number.isSafeInteger(record.rx_bytes) || record.rx_bytes < 0) return null
    if (!Number.isSafeInteger(record.tx_bytes) || record.tx_bytes < 0) return null
    if (typeof record.rx_bps !== "number" || !Number.isFinite(record.rx_bps) || record.rx_bps < 0)
        return null
    if (typeof record.tx_bps !== "number" || !Number.isFinite(record.tx_bps) || record.tx_bps < 0)
        return null

    if (record.type === "conn") {
        // `state` is TCP-only upstream; UDP conn records legitimately omit it.
        if (typeof record.src_ip !== "string" || record.src_ip === "") return null
        if (typeof record.dst_ip !== "string" || record.dst_ip === "") return null
        if (!Number.isSafeInteger(record.src_port) || record.src_port < 0) return null
        if (!Number.isSafeInteger(record.dst_port) || record.dst_port < 0) return null
        if (typeof record.proto !== "string" || record.proto === "") return null
        return {
            kind: "conn",
            ts: record.ts,
            pid: String(record.pid),
            comm: record.comm,
            src: record.src_ip,
            sport: record.src_port,
            dst: record.dst_ip,
            dport: record.dst_port,
            proto: record.proto,
            rx: record.rx_bytes,
            tx: record.tx_bytes
        }
    }

    if (!Number.isInteger(record.conns) || record.conns < 0) return null
    return {
        kind: "process",
        ts: record.ts,
        pid: String(record.pid),
        comm: record.comm,
        rx: record.rx_bytes,
        tx: record.tx_bytes
    }
}

// pktz keeps one kernel counter per PID, created at zero when pktz loads and
// continued for the PID's lifetime (and across PID reuse until LRU eviction).
// Baselines are therefore keyed by PID and retained while pktz runs: a PID
// never seen before contributes its full counter, a shrunk counter (evicted
// and recreated) contributes its new value, and a PID that skipped frames
// resumes from its retained baseline instead of being counted twice.
const PKTZ_RETAINED_PIDS = 4096

function commitPktzBatch(batch, lastCum, connCum, elapsed, commByPid, pendingDelta, unattributedKey) {
    const previousCum = lastCum ?? {}
    const previousConnCum = connCum ?? {}
    const fallbackKey = typeof unattributedKey === "string" && unattributedKey !== ""
        ? unattributedKey : "__unattributed_process"
    const entries = (batch ?? []).filter(entry => entry && entry.kind !== "conn"
        && typeof entry.pid === "string" && typeof entry.comm === "string")
    const entryByPid = new Map(entries.map(entry => [entry.pid, entry]))
    const presentPids = new Set(entryByPid.keys())
    const nextCum = Object.keys(previousCum).length + presentPids.size > PKTZ_RETAINED_PIDS
        ? {} : Object.assign({}, previousCum)
    const nextConnCum = {}
    const accounting = {}
    const rates = {}

    // Names resolve per PID from the full command line; drop a name when the
    // PID is gone or exec'd into another program (comm changed).
    const nextComm = {}
    for (const pid in (commByPid ?? {})) {
        const previous = previousCum[pid]
        const entry = entryByPid.get(pid)
        if (entry && (!previous || previous.comm === entry.comm))
            nextComm[pid] = commByPid[pid]
    }
    const nextPending = {}
    for (const entryId in (pendingDelta ?? {})) {
        const parked = pendingDelta[entryId]
        if (!parked || typeof parked !== "object") continue
        if (presentPids.has(String(parked.pid))) {
            nextPending[entryId] = Object.assign({}, parked)
        } else {
            addTraffic(accounting, parked.fallback || fallbackKey, bytes(parked.rx), bytes(parked.tx))
        }
    }

    // Per-process excluded-endpoint byte deltas from conn records. Process
    // counters stay authoritative (conn coverage has gaps upstream); conn
    // deltas only carve the excluded share back out. A first-sighted conn
    // contributes its full cumulative bytes, matching first-sighted process
    // counters. Conn counter shrink establishes a fresh baseline without
    // subtracting.
    const excludedDelta = {}
    for (const entry of (batch ?? [])) {
        if (!entry || entry.kind !== "conn") continue
        const connId = `${entry.pid}|${entry.proto}|${entry.src}:${entry.sport}|${entry.dst}:${entry.dport}`
        const previous = previousConnCum[connId]
        nextConnCum[connId] = { rx: entry.rx, tx: entry.tx }
        if (!excludedTrafficEndpoint(entry.src) && !excludedTrafficEndpoint(entry.dst))
            continue
        const drx = previous ? entry.rx - previous.rx : entry.rx
        const dtx = previous ? entry.tx - previous.tx : entry.tx
        if (drx < 0 || dtx < 0) continue
        const sum = excludedDelta[entry.pid] ?? { rx: 0, tx: 0 }
        sum.rx += drx
        sum.tx += dtx
        excludedDelta[entry.pid] = sum
    }

    const unresolved = new Set()
    for (const entry of entries) {
        const previous = previousCum[entry.pid]
        nextCum[entry.pid] = { rx: entry.rx, tx: entry.tx, comm: entry.comm }
        const reset = !previous || entry.rx < previous.rx || entry.tx < previous.tx
        const baseRx = reset ? 0 : previous.rx
        const baseTx = reset ? 0 : previous.tx
        const excluded = excludedDelta[entry.pid] ?? { rx: 0, tx: 0 }
        const drx = Math.max(0, entry.rx - baseRx - excluded.rx)
        const dtx = Math.max(0, entry.tx - baseTx - excluded.tx)
        const name = nextComm[entry.pid]
        if (name === undefined) unresolved.add(entry.pid)
        if (drx + dtx === 0) continue
        if (name === undefined) {
            const parked = nextPending[entry.pid] ?? { pid: entry.pid, rx: 0, tx: 0, fallback: entry.comm }
            parked.rx += drx
            parked.tx += dtx
            parked.fallback = entry.comm
            nextPending[entry.pid] = parked
        } else {
            addTraffic(accounting, name, drx, dtx)
        }
        if (elapsed > 0) {
            const label = name ?? entry.comm
            const rate = rates[label] ?? { name: label, down: 0, up: 0 }
            rate.down += drx / elapsed
            rate.up += dtx / elapsed
            rates[label] = rate
        }
    }
    for (const entryId in nextPending) {
        const parked = nextPending[entryId]
        const name = nextComm[String(parked.pid)]
        if (name !== undefined) {
            addTraffic(accounting, name, parked.rx, parked.tx)
            delete nextPending[entryId]
        }
    }
    return {
        lastCum: nextCum,
        connCum: nextConnCum,
        commByPid: nextComm,
        pendingDelta: nextPending,
        accounting: Object.values(accounting),
        unresolvedPids: [...unresolved],
        rates: Object.values(rates)
            .filter(app => app.down + app.up >= 1)
            .sort((left, right) => (right.down + right.up) - (left.down + left.up))
    }
}

function ssAddress(token) {
    if (typeof token !== "string" || token === "") return ""
    if (token.startsWith("[")) {
        const end = token.indexOf("]")
        return end > 0 ? token.substring(1, end) : ""
    }
    const cut = token.lastIndexOf(":")
    return cut > 0 ? token.substring(0, cut) : token
}

// `ss -tinpH` pairs: the socket line carries state, queues, local/peer
// address:port and users:(...); the following info line carries cumulative
// bytes_received/bytes_sent. Sockets on excluded endpoints (loopback,
// tailscale ranges) are skipped so the fallback matches the meter's scope.
// Keyed per socket (owner + 4-tuple): summing per name would let a socket
// closing between polls cancel out bytes of a socket opened in the meantime.
function parseSsSockets(text) {
    const sockets = {}
    let socket = null
    for (const line of (text ?? "").split("\n")) {
        const pm = line.match(/users:\(\("([^"]+)",pid=(\d+)/)
        if (pm) {
            const tokens = line.trim().split(/\s+/)
            const local = ssAddress(tokens[3])
            const peer = ssAddress(tokens[4])
            socket = excludedTrafficEndpoint(local) || excludedTrafficEndpoint(peer)
                ? { excluded: true }
                : { key: `${pm[2]}|${tokens[3]}|${tokens[4]}`, name: pm[1] }
            continue
        }
        if (socket === null) continue
        const rx = line.match(/bytes_received:(\d+)/)
        const tx = line.match(/bytes_sent:(\d+)/)
        if (rx || tx) {
            if (!socket.excluded) {
                sockets[socket.key] = {
                    name: socket.name,
                    rx: rx ? parseInt(rx[1]) : 0,
                    tx: tx ? parseInt(tx[1]) : 0
                }
            }
            socket = null
        }
    }
    return sockets
}

// The first sample only establishes baselines: sockets alive then carry bytes
// from before monitoring started. Afterwards a new socket opened since the
// previous poll contributes all its bytes; bytes moved by a socket after the
// previous poll and before it closed are not observable.
function commitSsSample(previousSockets, sockets, elapsed) {
    const accounting = {}
    const rates = {}
    if (previousSockets === null || previousSockets === undefined)
        return { accounting: [], rates: [] }
    for (const key in (sockets ?? {})) {
        const socket = sockets[key]
        const previous = previousSockets[key]
        const reset = !previous || socket.rx < previous.rx || socket.tx < previous.tx
        const drx = reset ? socket.rx : socket.rx - previous.rx
        const dtx = reset ? socket.tx : socket.tx - previous.tx
        if (drx + dtx === 0) continue
        addTraffic(accounting, socket.name, drx, dtx)
        if (elapsed > 0) {
            const rate = rates[socket.name] ?? { name: socket.name, down: 0, up: 0 }
            rate.down += drx / elapsed
            rate.up += dtx / elapsed
            rates[socket.name] = rate
        }
    }
    return {
        accounting: Object.values(accounting),
        rates: Object.values(rates)
            .filter(app => app.down + app.up >= 1)
            .sort((left, right) => (right.down + right.up) - (left.down + left.up))
    }
}

function nethogsCommand(seconds) {
    return ["stdbuf", "-oL", "nethogs", "-t", "-C", "-v", "2", "-d", String(seconds)]
}

function parseNethogsLine(data) {
    if (typeof data !== "string") return null
    const line = data.trim()
    if (line.startsWith("Refreshing:")) return { refresh: true }

    const parts = line.split("\t")
    if (parts.length < 3) return null
    const tx = Number(parts[parts.length - 2])
    const rx = Number(parts[parts.length - 1])
    if (!Number.isFinite(tx) || !Number.isFinite(rx) || tx < 0 || rx < 0) return null

    const idPart = parts.slice(0, parts.length - 2).join("\t")
    const unknown = idPart.match(/^unknown (TCP|UDP)\/0\/0$/)
    if (unknown) {
        return { cmdline: `__unattributed_${unknown[1].toLowerCase()}`, pid: "0", rx, tx }
    }
    if (/^unknown \S+\//.test(idPart)) return null

    const match = idPart.match(/^(.*)\/(\d+)\/(\d+)$/)
    if (!match || match[2] === "0") return null
    return { cmdline: match[1], pid: match[2], rx, tx }
}

// Interpreters and launchers run many unrelated programs; the program they
// run, not the interpreter, is the app. Generic entry-point names (index.js,
// /opt/komari/agent) are replaced by the nearest meaningful directory.
const INTERPRETER = /^(python[0-9.]*|pypy[0-9.]*|node|nodejs|bun|deno|ruby[0-9.]*|perl[0-9.]*|php[0-9.]*|java|lua[0-9.]*|sh|bash|zsh|dash|fish|tsx|ts-node)$/
const LAUNCHER = /^(npm|npx|pnpm|pnpx|yarn|bunx|uv|uvx|pipx)$/
const LAUNCHER_VERBS = new Set(["exec", "run", "x", "dlx", "tool", "start"])
// Flags whose next argument is a value, not the program.
const VALUE_FLAGS = new Set(["-W", "-X", "-Q", "-r", "--require", "--import", "--loader",
    "-cp", "-classpath", "--class-path", "-p", "--package", "--from", "--with", "--python"])
// Flags after which the program is inline code: keep the interpreter name.
const INLINE_FLAGS = new Set(["-c", "-e", "--eval", "-p", "--print"])
const GENERIC_BASE = new Set(["agent", "app", "cli", "client", "daemon", "index", "main",
    "__main__", "run", "server", "service", "start", "worker"])
const SKIP_DIR = new Set(["bin", "sbin", "lib", "lib64", "libexec", "dist", "build", "out",
    "src", "target", "release", "debug", "demos", "node_modules", "current", "usr", "local",
    "opt", "share", "scripts", "cjs", "esm", "mjs"])
const SCRIPT_EXT = /\.(py|pyw|js|mjs|cjs|ts|mts|jar|sh|bash|rb|pl|php|lua|exe)$/i

function pathParts(path) {
    return path.split(/[\\/]+/).filter(part => part !== "")
}

// Name of the program at `path`: basename without script extension; a generic
// basename falls back to the closest non-structural parent directory.
function programName(path) {
    const parts = pathParts(path)
    if (parts.length === 0) return ""
    let base = parts[parts.length - 1]
    // npm package specs: @scope/pkg@1.2.3 -> pkg
    if (base.indexOf("@", 1) > 0) base = base.substring(0, base.indexOf("@", 1))
    base = base.replace(SCRIPT_EXT, "")
    if (!GENERIC_BASE.has(base.toLowerCase())) return base
    for (let index = parts.length - 2; index >= 0; index--) {
        const dir = parts[index]
        if (!SKIP_DIR.has(dir.toLowerCase()) && !dir.startsWith(".") && !dir.startsWith("@"))
            return dir
    }
    return base
}

// Display name for a process command line (argv joined by spaces, as nethogs
// and `ps -o args` print it). Null when argv[0] cannot identify the program
// (`/proc/self/exe`, `exe`), so the caller resolves it another way.
function appName(cmdline) {
    if (typeof cmdline !== "string") return null
    const argv = cmdline.trim().split(/\s+/).filter(arg => arg !== "")
    if (argv.length === 0) return null
    const exe = argv[0].replace(/^-/, "")
    const parts = pathParts(exe)
    const base = parts.length > 0 ? parts[parts.length - 1] : ""
    if (base === "" || base === "exe") return null
    const interpreter = base.replace(SCRIPT_EXT, "")
    const isInterpreter = INTERPRETER.test(interpreter)
    const isLauncher = LAUNCHER.test(interpreter)
    if (!isInterpreter && !isLauncher) return programName(exe)

    for (let index = 1; index < argv.length; index++) {
        const arg = argv[index]
        if (INLINE_FLAGS.has(arg) && !(isLauncher && arg === "-p")) return interpreter
        if (arg === "-m" || arg === "-jar") {
            const target = argv[index + 1]
            return target ? programName(arg === "-m" ? target.split(".")[0] : target) : interpreter
        }
        if (VALUE_FLAGS.has(arg)) { index++; continue }
        if (arg.startsWith("-")) continue
        if (isLauncher && LAUNCHER_VERBS.has(arg)) continue
        // java: a main class, not a path -> its simple name
        if (interpreter === "java" && !arg.includes("/")) {
            const segments = arg.split(".")
            return segments[segments.length - 1] || interpreter
        }
        return programName(arg) || interpreter
    }
    return interpreter
}

// `ps -o pid=,comm=` then a `--` line then `ps -ww -o pid=,args=` for the
// same PIDs. comm (15 chars) is only the fallback when args cannot name the
// program, e.g. Electron's argv[0] of /proc/self/exe.
function parsePsNames(text) {
    const comm = {}
    const args = {}
    let target = comm
    for (const line of (text ?? "").split("\n")) {
        if (line.trim() === "--") { target = args; continue }
        const match = line.trim().match(/^(\d+)\s+(.+)$/)
        if (match) target[match[1]] = match[2]
    }
    const names = {}
    for (const pid in comm) {
        const name = appName(args[pid]) ?? comm[pid].trim()
        if (name !== "") names[pid] = name
    }
    return names
}

function psNamesCommand(pids) {
    const list = Array.from(pids ?? [], pid => String(pid)).filter(pid => /^\d+$/.test(pid)).join(",")
    return ["sh", "-c", 'ps -o pid=,comm= -p "$1"; echo --; ps -ww -o pid=,args= -p "$1"', "sh", list]
}

function addTraffic(map, name, rx, tx) {
    const row = map[name] ?? { name, rx: 0, tx: 0 }
    row.rx += rx
    row.tx += tx
    map[name] = row
}

function commitNethogsBatch(batch, lastCum, elapsed, commByPid, pendingDelta) {
    const previousCum = lastCum ?? {}
    const nextCum = {}
    const accounting = {}
    const rates = {}
    const entries = batch ?? []
    const activeEntryIds = new Set(entries.map(entry => `${entry.cmdline}/${entry.pid}`))
    const discontinuousPids = new Set()
    for (const entry of entries) {
        const previous = previousCum[`${entry.cmdline}/${entry.pid}`]
        if (previous && (entry.rx < previous.rx || entry.tx < previous.tx))
            discontinuousPids.add(String(entry.pid))
    }
    const continuousPids = new Set()
    for (const entry of entries) {
        const entryId = `${entry.cmdline}/${entry.pid}`
        if (previousCum[entryId] && !discontinuousPids.has(String(entry.pid)))
            continuousPids.add(String(entry.pid))
    }

    const nextComm = {}
    for (const pid in (commByPid ?? {})) {
        if (continuousPids.has(String(pid))) nextComm[pid] = commByPid[pid]
    }
    const nextPending = {}
    for (const entryId in (pendingDelta ?? {})) {
        const parked = pendingDelta[entryId]
        if (activeEntryIds.has(entryId) && previousCum[entryId]
                && !discontinuousPids.has(String(parked.pid))) {
            nextPending[entryId] = Object.assign({}, parked)
        } else {
            addTraffic(accounting, parked.fallback || "__unattributed_process", parked.rx, parked.tx)
        }
    }

    for (const entry of entries) {
        const entryId = `${entry.cmdline}/${entry.pid}`
        const previous = previousCum[entryId]
        nextCum[entryId] = { rx: entry.rx, tx: entry.tx }
        // nethogs counters start at zero when nethogs starts tracking a
        // process and never shrink while it does (closed-connection bytes are
        // kept). A row that is new, or shrank, was (re)created after nethogs
        // dropped it for idling: every byte it reports is new traffic.
        const reset = !previous || entry.rx < previous.rx || entry.tx < previous.tx
        const drx = reset ? entry.rx : entry.rx - previous.rx
        const dtx = reset ? entry.tx : entry.tx - previous.tx
        if (drx === 0 && dtx === 0) continue

        const name = entry.cmdline.startsWith("__unattributed_")
            ? entry.cmdline : (appName(entry.cmdline) ?? nextComm[entry.pid] ?? null)
        if (name === null) {
            const parked = nextPending[entryId] ?? { pid: entry.pid, rx: 0, tx: 0 }
            parked.rx += drx
            parked.tx += dtx
            nextPending[entryId] = parked
            continue
        }

        addTraffic(accounting, name, drx, dtx)
        if (elapsed > 0) {
            const rate = rates[name] ?? { name, down: 0, up: 0 }
            rate.down += drx / elapsed
            rate.up += dtx / elapsed
            rates[name] = rate
        }
    }

    for (const entryId in nextPending) {
        const parked = nextPending[entryId]
        const name = nextComm[parked.pid]
        if (name !== undefined) {
            addTraffic(accounting, name, parked.rx, parked.tx)
            delete nextPending[entryId]
        }
    }

    const unresolvedPids = [...new Set(Object.values(nextPending).map(parked => String(parked.pid)))]
    const activePids = [...new Set(entries.map(entry => String(entry.pid)))]
    const activeEntryIdList = entries.map(entry => `${entry.cmdline}/${entry.pid}`)

    return {
        lastCum: nextCum,
        commByPid: nextComm,
        pendingDelta: nextPending,
        accounting: Object.values(accounting),
        rates: Object.values(rates)
            .filter(app => app.down + app.up >= 1)
            .sort((a, b) => (b.down + b.up) - (a.down + a.up)),
        unresolvedPids,
        activePids,
        activeEntryIds: activeEntryIdList
    }
}
