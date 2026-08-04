.pragma library

const DAYS_PER_WEEK = 7
const ISO_THURSDAY_INDEX = 3
const ISO_REFERENCE_DAY = 4
const JANUARY_INDEX = 0
const LOCAL_NOON_HOUR = 12
const MILLISECONDS_PER_DAY = 86400000

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

function dateKey(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`
}

function dayOrdinal(key) {
    const date = validDayKey(key)
    return date ? Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / MILLISECONDS_PER_DAY : null
}

function isoWeekInfo(key) {
    const date = validDayKey(key)
    if (!date)
        return { year: 0, week: 0, startKey: "", endKey: "" }

    const weekday = (date.getDay() + DAYS_PER_WEEK - 1) % DAYS_PER_WEEK
    const startKey = shiftDayKey(key, -weekday)
    const thursday = validDayKey(shiftDayKey(startKey, ISO_THURSDAY_INDEX))
    const year = thursday.getFullYear()
    const januaryFourth = new Date(year, JANUARY_INDEX, ISO_REFERENCE_DAY, LOCAL_NOON_HOUR)
    const januaryWeekday = (januaryFourth.getDay() + DAYS_PER_WEEK - 1) % DAYS_PER_WEEK
    const firstStartKey = shiftDayKey(dateKey(januaryFourth), -januaryWeekday)
    const week = Math.floor((dayOrdinal(startKey) - dayOrdinal(firstStartKey)) / DAYS_PER_WEEK) + 1
    return { year, week, startKey, endKey: shiftDayKey(startKey, DAYS_PER_WEEK - 1) }
}

function recordForKey(key, records, today) {
    if (key === today.k)
        return today
    const stored = records.get(key)
    const total = stored ? recordedSeconds(stored.total) : null
    return total === null ? null : { k: key, total, apps: rankingFromList(stored.apps) }
}

function aggregatePeriod(options) {
    const appTotals = {}
    let total = 0
    let coverage = 0
    for (let index = 0; index < options.span; index++) {
        const record = recordForKey(shiftDayKey(options.startKey, index), options.records, options.today)
        if (!record)
            continue
        total += record.total
        coverage++
        for (const app of record.apps)
            appTotals[app.n] = (appTotals[app.n] || 0) + app.s
    }
    return { total, coverage, expectedDays: options.span, apps: rankingFromMap(appTotals) }
}

function weekSeries(options) {
    const days = []
    for (let index = 0; index < DAYS_PER_WEEK; index++) {
        const key = shiftDayKey(options.startKey, index)
        const record = key <= options.today.k ? recordForKey(key, options.records, options.today) : null
        days.push({ k: key, total: record ? record.total : null })
    }
    return days
}

function comparedApps(currentApps, previousApps, available) {
    const previousByName = new Map(previousApps.map(app => [app.n, app.s]))
    return currentApps.map(app => {
        const previous = available ? (previousByName.has(app.n) ? previousByName.get(app.n) : 0) : null
        return { n: app.n, s: app.s, previous, delta: available ? app.s - previous : null }
    })
}

function emptyWeeklyReport() {
    const period = { startKey: "", endKey: "", total: 0, coverage: 0,
                     expectedDays: 0, apps: [] }
    const current = { startKey: "", endKey: "", total: 0, coverage: 0,
                      expectedDays: 0, days: [], apps: [] }
    return { info: { year: 0, week: 0, startKey: "", endKey: "" },
             current, previous: period, comparisonAvailable: false, totalDelta: null }
}

function weeklyReport(options) {
    const input = options && typeof options === "object" ? options : {}
    const info = isoWeekInfo(input.todayKey)
    const todayDate = validDayKey(input.todayKey)
    if (!todayDate)
        return emptyWeeklyReport()

    const records = latestDays(input.days)
    const today = { k: input.todayKey, total: seconds(input.todayTotal),
                    apps: rankingFromMap(input.todayApps) }
    const weekday = (todayDate.getDay() + DAYS_PER_WEEK - 1) % DAYS_PER_WEEK
    const expectedDays = weekday + 1
    const currentData = aggregatePeriod({ startKey: info.startKey, span: expectedDays,
                                          records, today })
    const previousStartKey = shiftDayKey(info.startKey, -DAYS_PER_WEEK)
    const previousData = aggregatePeriod({ startKey: previousStartKey, span: expectedDays,
                                           records, today })
    const comparisonAvailable = currentData.coverage === expectedDays
        && previousData.coverage === expectedDays
    const current = { startKey: info.startKey, endKey: info.endKey,
                      total: currentData.total, coverage: currentData.coverage, expectedDays,
                      days: weekSeries({ startKey: info.startKey, records, today }),
                      apps: comparedApps(currentData.apps, previousData.apps, comparisonAvailable) }
    const previous = { startKey: previousStartKey,
                       endKey: shiftDayKey(previousStartKey, expectedDays - 1),
                       total: previousData.total, coverage: previousData.coverage,
                       expectedDays, apps: previousData.apps }
    return { info, current, previous, comparisonAvailable,
             totalDelta: comparisonAvailable ? current.total - previous.total : null }
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
