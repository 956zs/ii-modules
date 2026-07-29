.pragma library

function seconds(value) {
    const number = Number(value)
    return Number.isFinite(number) && number > 0 ? number : 0
}

function count(value) {
    const number = Number(value)
    return Number.isFinite(number) && number > 0 ? Math.round(number) : 0
}

function recordedSeconds(value) {
    return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : null
}

function validDayKey(key) {
    const match = typeof key === "string" ? key.match(/^(\d{4})-(\d{2})-(\d{2})$/) : null
    if (!match)
        return null
    const year = Number(match[1])
    const month = Number(match[2])
    const day = Number(match[3])
    const date = new Date(year, month - 1, day, 12)
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
        ? date : null
}

function shiftDayKey(key, delta) {
    const date = validDayKey(key)
    const amount = Number(delta)
    if (!date || !Number.isInteger(amount))
        return ""

    date.setDate(date.getDate() + amount)
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
}

function rankingFromMap(apps) {
    if (!apps || typeof apps !== "object" || Array.isArray(apps))
        return []
    return Object.entries(apps)
        .map(([n, value]) => ({ n, s: seconds(value) }))
        .filter(app => typeof app.n === "string" && app.n !== "" && app.s >= 1)
        .sort((a, b) => b.s - a.s)
}

function rankingFromList(apps) {
    if (!Array.isArray(apps))
        return []
    return apps
        .filter(app => app && typeof app.n === "string" && app.n !== "")
        .map(app => ({ n: app.n, s: seconds(app.s) }))
        .filter(app => app.s >= 1)
        .sort((a, b) => b.s - a.s)
}

function latestDays(days) {
    const records = new Map()
    if (!Array.isArray(days))
        return records
    for (const day of days) {
        if (day && validDayKey(day.k))
            records.set(day.k, day)
    }
    return records
}

function period(key, records, startOffset, span) {
    const startKey = shiftDayKey(key, startOffset)
    const endKey = shiftDayKey(startKey, span - 1)
    if (startKey === "" || endKey === "")
        return { startKey: "", endKey: "", average: 0, coverage: 0, span, days: [] }

    const out = []
    let sum = 0
    let coverage = 0
    for (let index = 0; index < span; index++) {
        const dayKey = shiftDayKey(startKey, index)
        const record = records.get(dayKey)
        const total = record ? recordedSeconds(record.total) : null
        out.push({ k: dayKey, total })
        if (total !== null) {
            sum += total
            coverage++
        }
    }
    return { startKey, endKey, average: coverage > 0 ? sum / coverage : 0,
             coverage, span, days: out }
}

function periodSummary(todayKey, days, span) {
    const length = Number(span)
    const safeSpan = Number.isInteger(length) && length > 0 && length <= 31 ? length : 7
    if (!validDayKey(todayKey)) {
        const current = { startKey: "", endKey: "", average: 0, coverage: 0,
                          span: safeSpan, days: [] }
        const previous = { startKey: "", endKey: "", average: 0, coverage: 0,
                           span: safeSpan, days: [] }
        return { current, previous, delta: null }
    }

    const records = latestDays(days)
    const current = period(todayKey, records, -safeSpan, safeSpan)
    const previous = period(todayKey, records, -safeSpan * 2, safeSpan)
    const delta = current.coverage > 0 && previous.coverage > 0
        ? current.average - previous.average : null
    return { current, previous, delta }
}

function normalizedHours(hours) {
    if (!Array.isArray(hours) || hours.length !== 24)
        return null
    const normalized = hours.map(value => recordedSeconds(value))
    return normalized.some(value => value === null) ? null : normalized
}

function hourHeatmap(todayKey, days, span) {
    const length = Number(span)
    const safeSpan = Number.isInteger(length) && length > 0 && length <= 31 ? length : 28
    const values = Array.from({ length: 7 }, () => new Array(24).fill(0))
    const counts = Array.from({ length: 7 }, () => new Array(24).fill(0))
    const startKey = shiftDayKey(todayKey, -safeSpan)
    const endKey = shiftDayKey(todayKey, -1)
    if (startKey === "" || endKey === "")
        return { startKey: "", endKey: "", coverage: 0, values, peak: null }

    let coverage = 0
    for (const [key, record] of latestDays(days)) {
        if (key < startKey || key > endKey)
            continue
        const hours = normalizedHours(record.hours)
        if (!hours)
            continue
        const date = validDayKey(key)
        const dow = (date.getDay() + 6) % 7
        for (let hour = 0; hour < 24; hour++) {
            values[dow][hour] += hours[hour] / 60
            counts[dow][hour]++
        }
        coverage++
    }

    let peak = null
    for (let dow = 0; dow < 7; dow++) {
        for (let hour = 0; hour < 24; hour++) {
            values[dow][hour] = counts[dow][hour] > 0 ? values[dow][hour] / counts[dow][hour] : 0
            if (values[dow][hour] > 0 && (!peak || values[dow][hour] > peak.minutes))
                peak = { dow, hour, minutes: values[dow][hour] }
        }
    }
    return { startKey, endKey, coverage, values, peak }
}

function dayRecord(key, todayKey, todayTotal, todayApps, aiUnion, aiSum, aiPeak, days) {
    if (typeof key !== "string" || key === "")
        return { k: "", total: 0, apps: [], aiU: 0, aiS: 0, aiP: 0, isToday: false, hasData: false }

    if (key === todayKey) {
        const apps = rankingFromMap(todayApps)
        const total = seconds(todayTotal)
        const aiU = seconds(aiUnion)
        const aiS = seconds(aiSum)
        const aiP = count(aiPeak)
        return { k: key, total, apps, aiU, aiS, aiP, isToday: true,
                 hasData: total >= 1 || aiU >= 1 }
    }

    let record = null
    if (Array.isArray(days)) {
        for (let index = days.length - 1; index >= 0; index--) {
            if (days[index] && days[index].k === key) {
                record = days[index]
                break
            }
        }
    }
    if (!record)
        return { k: key, total: 0, apps: [], aiU: 0, aiS: 0, aiP: 0, isToday: false, hasData: false }

    const apps = rankingFromList(record.apps)
    const total = seconds(record.total)
    const aiU = seconds(record.aiU)
    const aiS = seconds(record.aiS)
    const aiP = count(record.aiP)
    return { k: key, total, apps, aiU, aiS, aiP, isToday: false,
             hasData: total >= 1 || aiU >= 1 }
}
