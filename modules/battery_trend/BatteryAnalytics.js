.pragma library

function finiteNumber(value) {
    return typeof value === "number" && isFinite(value)
}

function round1(value) {
    return Math.round(value * 10) / 10
}

function round2(value) {
    return Math.round(value * 100) / 100
}

function validAggregate(entry) {
    return Array.isArray(entry) && entry.length >= 8
        && finiteNumber(entry[0]) && finiteNumber(entry[6]) && entry[6] >= 0
        && finiteNumber(entry[7]) && entry[7] >= 0
}

function validAccumulator(accumulator) {
    if (accumulator === null || typeof accumulator !== "object")
        return false
    const fields = ["t", "n", "mn", "mx", "sum", "wSum", "wN",
                    "chg", "awake", "dis", "disSec"]
    for (let i = 0; i < fields.length; i++) {
        if (!finiteNumber(accumulator[fields[i]]))
            return false
    }
    return accumulator.n > 0 && accumulator.mn >= 0 && accumulator.mx >= 0
        && accumulator.sum >= 0 && accumulator.wSum >= 0 && accumulator.wN >= 0
        && accumulator.chg >= 0 && accumulator.awake >= 0
        && accumulator.dis >= 0 && accumulator.disSec >= 0
}

function validSessionAccumulator(session) {
    return session !== null && typeof session === "object"
        && (session.k === "c" || session.k === "d")
        && finiteNumber(session.t0) && finiteNumber(session.p0)
}

function dayStart(timestamp) {
    const date = new Date(timestamp * 1000)
    return Math.floor(new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() / 1000)
}

function addAggregate(days, entry, replace) {
    if (!validAggregate(entry))
        return
    const day = dayStart(entry[0])
    if (!days[day] || replace)
        days[day] = {t: entry[0], dis: entry[6], disSec: entry[7]}
    else {
        days[day].dis += entry[6]
        days[day].disSec += entry[7]
    }
}

function aggregateDays(daily, hourly, raw, gapSec, dayAccumulator) {
    const days = {}

    // Hourly is a fallback when daily retention is disabled or a daily bucket
    // is absent. A finalized daily bucket is authoritative for its day.
    const hourlyDays = {}
    const hourlyEntries = Array.isArray(hourly) ? hourly : []
    for (let i = 0; i < hourlyEntries.length; i++)
        addAggregate(hourlyDays, hourlyEntries[i], false)
    const hourlyKeys = Object.keys(hourlyDays)
    for (let i = 0; i < hourlyKeys.length; i++)
        days[hourlyKeys[i]] = hourlyDays[hourlyKeys[i]]

    const dailyEntries = Array.isArray(daily) ? daily : []
    for (let i = 0; i < dailyEntries.length; i++)
        addAggregate(days, dailyEntries[i], true)

    // Raw covers the newest, not-yet-finalized period when an older blob has
    // no usable current accumulator. Never overlap a finalized/coarser day.
    const rawDays = {}
    const rawEntries = Array.isArray(raw) ? raw : []
    const maxGap = finiteNumber(gapSec) && gapSec > 0 ? gapSec : 300
    for (let i = 1; i < rawEntries.length; i++) {
        const previous = rawEntries[i - 1]
        const current = rawEntries[i]
        if (!Array.isArray(previous) || previous.length < 4
                || !Array.isArray(current) || current.length < 4)
            continue
        const t0 = previous[0]
        const t1 = current[0]
        const p0 = previous[1]
        const p1 = current[1]
        if (!finiteNumber(t0) || !finiteNumber(t1)
                || !finiteNumber(p0) || !finiteNumber(p1)
                || !finiteNumber(current[3]))
            continue
        const dt = t1 - t0
        if (dt <= 0 || dt > maxGap || current[3] !== 0)
            continue
        const day = dayStart(t1)
        if (!rawDays[day])
            rawDays[day] = {t: day, dis: 0, disSec: 0}
        rawDays[day].disSec += dt
        if (p0 > p1)
            rawDays[day].dis += p0 - p1
    }
    const rawKeys = Object.keys(rawDays)
    for (let i = 0; i < rawKeys.length; i++) {
        const day = rawKeys[i]
        if (!days[day])
            days[day] = rawDays[day]
    }

    if (validAccumulator(dayAccumulator)) {
        const day = dayStart(dayAccumulator.t)
        days[day] = {
            t: dayAccumulator.t,
            dis: dayAccumulator.dis,
            disSec: dayAccumulator.disSec
        }
    }

    return days
}

function windowStats(days, timestamp, windowSec) {
    let dis = 0
    let disSec = 0
    const since = timestamp - windowSec
    const keys = Object.keys(days)
    for (let i = 0; i < keys.length; i++) {
        const entry = days[keys[i]]
        if (entry.t >= since) {
            dis += entry.dis
            disSec += entry.disSec
        }
    }
    return {
        dis: round1(dis),
        rate: disSec > 60 ? round1(dis / (disSec / 3600)) : 0,
        cycles: round2(dis / 100)
    }
}

function todayStats(dayAccumulator) {
    if (!validAccumulator(dayAccumulator))
        return {dis: 0, rate: 0, avgW: 0, chgH: 0}
    const wN = finiteNumber(dayAccumulator.wN) && dayAccumulator.wN > 0
        ? dayAccumulator.wN : 0
    const wSum = finiteNumber(dayAccumulator.wSum) ? dayAccumulator.wSum : 0
    const chargedSec = finiteNumber(dayAccumulator.chg) && dayAccumulator.chg > 0
        ? dayAccumulator.chg : 0
    return {
        dis: round1(dayAccumulator.dis),
        rate: dayAccumulator.disSec > 60
            ? round1(dayAccumulator.dis / (dayAccumulator.disSec / 3600)) : 0,
        avgW: wN > 0 ? round2(wSum / wN) : 0,
        chgH: round1(chargedSec / 3600)
    }
}

function sessionStats(sessions) {
    let dodSum = 0
    let dodN = 0
    let chargeStartSum = 0
    let chargeEndSum = 0
    let chargeN = 0
    const entries = Array.isArray(sessions) ? sessions : []
    for (let i = 0; i < entries.length; i++) {
        const session = entries[i]
        if (!Array.isArray(session) || session.length < 5
                || (session[0] !== "c" && session[0] !== "d")
                || !finiteNumber(session[1]) || !finiteNumber(session[2])
                || !finiteNumber(session[3]) || !finiteNumber(session[4])
                || session[2] <= session[1])
            continue
        if (session[0] === "d" && session[3] - session[4] >= 3
                && session[2] - session[1] >= 600) {
            dodSum += session[3] - session[4]
            dodN++
        }
        if (session[0] === "c" && session[4] - session[3] >= 3) {
            chargeStartSum += session[3]
            chargeEndSum += session[4]
            chargeN++
        }
    }
    return {
        dod: dodN > 0 ? round1(dodSum / dodN) : -1,
        chargeFrom: chargeN > 0 ? Math.round(chargeStartSum / chargeN) : -1,
        chargeTo: chargeN > 0 ? Math.round(chargeEndSum / chargeN) : -1
    }
}

function healthStats(health) {
    const valid = []
    const entries = Array.isArray(health) ? health : []
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i]
        if (Array.isArray(entry) && entry.length >= 2
                && finiteNumber(entry[0]) && finiteNumber(entry[1]))
            valid.push(entry)
    }
    valid.sort((a, b) => a[0] - b[0])

    const now = valid.length > 0 ? valid[valid.length - 1][1] : -1
    let d30 = null
    let span = null
    let spanDays = 0
    if (valid.length >= 2) {
        const latest = valid[valid.length - 1]
        for (let i = 0; i < valid.length; i++) {
            if (latest[0] - valid[i][0] <= 30 * 86400) {
                if (latest[0] - valid[i][0] >= 6 * 86400)
                    d30 = round1(latest[1] - valid[i][1])
                break
            }
        }
        spanDays = Math.round((latest[0] - valid[0][0]) / 86400)
        if (spanDays >= 7)
            span = round1(latest[1] - valid[0][1])
    }
    return {hNow: now, h30: d30, hSpan: span, hSpanDays: spanDays}
}

function computeStats(timestamp, daily, hourly, raw, gapSec, dayAccumulator, sessions, health) {
    const days = aggregateDays(daily, hourly, raw, gapSec, dayAccumulator)
    const session = sessionStats(sessions)
    const healthValues = healthStats(health)
    return {
        today: todayStats(dayAccumulator),
        d7: windowStats(days, timestamp, 7 * 86400),
        d30: windowStats(days, timestamp, 30 * 86400),
        dod: session.dod,
        chargeFrom: session.chargeFrom,
        chargeTo: session.chargeTo,
        hNow: healthValues.hNow,
        h30: healthValues.h30,
        hSpan: healthValues.hSpan,
        hSpanDays: healthValues.hSpanDays
    }
}
