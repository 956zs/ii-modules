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

function restoreAccounting(serialized, bootId, now) {
    let state = null
    try {
        state = JSON.parse(serialized)
    } catch (error) {
        state = null
    }

    const currentDay = dayKey(now)
    const currentMonth = monthKey(now)
    const entries = Array.isArray(state?.apps) ? state.apps : []
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

function drainResolvedPending(pendingDelta, commByPid, activePids) {
    const active = new Set((activePids ?? []).map(pid => String(pid)))
    const nextComm = {}
    for (const pid in (commByPid ?? {})) {
        if (active.has(String(pid))) nextComm[pid] = commByPid[pid]
    }

    const nextPending = {}
    const accounting = {}
    for (const entryId in (pendingDelta ?? {})) {
        const parked = pendingDelta[entryId]
        const pid = String(parked.pid)
        if (!active.has(pid)) continue
        const name = nextComm[pid]
        if (name === undefined) {
            nextPending[entryId] = Object.assign({}, parked)
        } else {
            addTraffic(accounting, name, parked.rx, parked.tx)
        }
    }
    return {
        commByPid: nextComm,
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
        const name = typeof resolved === "string" && resolved !== "" ? resolved : fallback
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

function commitPktzBatch(batch, lastCum, connCum, elapsed) {
    const previousCum = lastCum ?? {}
    const previousConnCum = connCum ?? {}
    const nextCum = {}
    const nextConnCum = {}
    const accounting = {}
    const rates = {}

    // Per-process excluded-endpoint byte deltas from conn records. Process
    // counters stay authoritative (conn coverage has gaps upstream); conn
    // deltas only carve the excluded share back out. A first-sighted conn
    // contributes its full cumulative bytes: within one collector run those
    // bytes accrued inside the process counters being committed. Conn counter
    // shrink establishes a fresh baseline without subtracting.
    const excludedDelta = {}
    for (const entry of (batch ?? [])) {
        if (!entry || entry.kind !== "conn") continue
        const connId = `${entry.pid}/${entry.comm}|${entry.proto}|${entry.src}:${entry.sport}|${entry.dst}:${entry.dport}`
        const previous = previousConnCum[connId]
        nextConnCum[connId] = { rx: entry.rx, tx: entry.tx }
        if (!excludedTrafficEndpoint(entry.src) && !excludedTrafficEndpoint(entry.dst))
            continue
        const drx = previous ? entry.rx - previous.rx : entry.rx
        const dtx = previous ? entry.tx - previous.tx : entry.tx
        if (drx < 0 || dtx < 0) continue
        const entryId = `${entry.pid}/${entry.comm}`
        const sum = excludedDelta[entryId] ?? { rx: 0, tx: 0 }
        sum.rx += drx
        sum.tx += dtx
        excludedDelta[entryId] = sum
    }

    for (const entry of (batch ?? [])) {
        if (!entry || entry.kind === "conn") continue
        if (typeof entry.pid !== "string" || typeof entry.comm !== "string")
            continue
        const entryId = `${entry.pid}/${entry.comm}`
        const previous = previousCum[entryId]
        nextCum[entryId] = { rx: entry.rx, tx: entry.tx }
        if (!previous || entry.rx < previous.rx || entry.tx < previous.tx)
            continue

        const excluded = excludedDelta[entryId] ?? { rx: 0, tx: 0 }
        const drx = Math.max(0, entry.rx - previous.rx - excluded.rx)
        const dtx = Math.max(0, entry.tx - previous.tx - excluded.tx)
        if (drx + dtx === 0) continue
        addTraffic(accounting, entry.comm, drx, dtx)
        if (elapsed > 0) {
            const rate = rates[entry.comm] ?? { name: entry.comm, down: 0, up: 0 }
            rate.down += drx / elapsed
            rate.up += dtx / elapsed
            rates[entry.comm] = rate
        }
    }
    return {
        lastCum: nextCum,
        connCum: nextConnCum,
        accounting: Object.values(accounting),
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
function parseSsTotals(text) {
    const totals = {}
    let name = null
    let excluded = false
    for (const line of (text ?? "").split("\n")) {
        const pm = line.match(/users:\(\("([^"]+)",pid=\d+/)
        if (pm) {
            name = pm[1]
            const tokens = line.trim().split(/\s+/)
            const local = ssAddress(tokens[3])
            const peer = ssAddress(tokens[4])
            excluded = excludedTrafficEndpoint(local) || excludedTrafficEndpoint(peer)
            continue
        }
        if (name === null) continue
        const rx = line.match(/bytes_received:(\d+)/)
        const tx = line.match(/bytes_sent:(\d+)/)
        if (rx || tx) {
            if (!excluded) {
                totals[name] = totals[name] ?? { rx: 0, tx: 0 }
                totals[name].rx += rx ? parseInt(rx[1]) : 0
                totals[name].tx += tx ? parseInt(tx[1]) : 0
            }
            name = null
        }
    }
    return totals
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

function prettyName(cmdline, pid, commByPid) {
    const exe = cmdline.split(" ")[0]
    const base = exe.substring(exe.lastIndexOf("/") + 1)
    if (base === "exe" || base === "") return commByPid[pid] ?? null
    return base
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
            addTraffic(accounting, "__unattributed_process", parked.rx, parked.tx)
        }
    }

    for (const entry of entries) {
        const entryId = `${entry.cmdline}/${entry.pid}`
        const previous = previousCum[entryId]
        nextCum[entryId] = { rx: entry.rx, tx: entry.tx }
        if (!previous || entry.rx < previous.rx || entry.tx < previous.tx) continue

        const drx = entry.rx - previous.rx
        const dtx = entry.tx - previous.tx
        if (drx === 0 && dtx === 0) continue

        const name = prettyName(entry.cmdline, entry.pid, nextComm)
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
