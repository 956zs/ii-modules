function parseObject(serialized) {
    try {
        const value = JSON.parse(serialized)
        return value !== null && typeof value === "object" && !Array.isArray(value) ? value : {}
    } catch (error) {
        return {}
    }
}

function own(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key)
}

function validSchema(value) {
    return Number.isInteger(value) && value >= 0 ? value : 0
}

function migrateLegacyAccounting(raw) {
    if ((!own(raw, "acctState") || raw.acctState === "") && own(raw, "acctDayKey")) {
        const state = {
            v: 1,
            day: {
                k: raw.acctDayKey ?? "",
                rx: raw.acctDayRx ?? 0,
                tx: raw.acctDayTx ?? 0
            },
            month: {
                k: raw.acctMonthKey ?? "",
                rx: raw.acctMonthRx ?? 0,
                tx: raw.acctMonthTx ?? 0
            },
            sample: {
                rx: raw.acctSampleRx ?? 0,
                tx: raw.acctSampleTx ?? 0
            }
        }
        if (state.month.k !== "" && state.day.k.startsWith(state.month.k)) {
            state.month.rx = Math.max(state.month.rx, state.day.rx)
            state.month.tx = Math.max(state.month.tx, state.day.tx)
        }
        raw.acctState = JSON.stringify(state)
    }
    if ((!own(raw, "appAcctState") || raw.appAcctState === "") && own(raw, "appAcct")) {
        raw.appAcctState = JSON.stringify({
            v: 1,
            bootId: raw.appAcctBootId ?? "",
            apps: raw.appAcct ?? []
        })
    }
}

function migratePeriod(raw, defaults, currentSchema) {
    const schema = validSchema(raw.statsPeriodSchema)
    const storedPeriod = typeof raw.statsPeriod === "string"
        ? raw.statsPeriod : defaults.statsPeriod
    const period = storedPeriod === "boot" || storedPeriod === "month"
        ? storedPeriod : "today"
    raw.statsPeriod = schema < currentSchema && period === "boot" ? "today" : period
    raw.statsPeriodSchema = Math.max(schema, currentSchema)
}

function prepareConfig(serialized, defaults, owner, currentSchema) {
    const original = parseObject(serialized)
    const raw = Object.assign({}, original)
    const schema = validSchema(raw.statsPeriodSchema)
    const futureSchema = schema > currentSchema

    if (!futureSchema) {
        migrateLegacyAccounting(raw)
        migratePeriod(raw, defaults, currentSchema)
        for (const key in defaults) {
            if (!own(raw, key)) raw[key] = defaults[key]
        }
    }

    const values = {}
    for (const key in defaults) {
        values[key] = own(raw, key) ? raw[key] : defaults[key]
    }
    const output = futureSchema ? serialized : JSON.stringify(raw)
    return {
        values,
        serialized: output,
        futureSchema,
        shouldWrite: owner && !futureSchema && output !== serialized
    }
}

function decodeSettingIntent(key, serializedValue) {
    const reject = { accepted: false }
    if (typeof key !== "string" || typeof serializedValue !== "string") return reject

    let value
    try {
        value = JSON.parse(serializedValue)
    } catch (error) {
        return reject
    }

    const oneOf = (candidate, choices) => typeof candidate === "string"
        && choices.includes(candidate)
    const integerIn = (candidate, minimum, maximum) => Number.isInteger(candidate)
        && candidate >= minimum && candidate <= maximum
    let accepted = false
    if (key === "displayMode")
        accepted = oneOf(value, ["auto", "stacked", "horizontal"])
    else if (key === "autoStackMaxWidth")
        accepted = integerIn(value, 800, 7680)
    else if (key === "stackedShowIcons" || key === "appMonitoring")
        accepted = typeof value === "boolean"
    else if (key === "statsPeriod")
        accepted = oneOf(value, ["boot", "today", "month"])
    else if (key === "updateInterval")
        accepted = integerIn(value, 500, 10000)
    else if (key === "breatheThresholdKB")
        accepted = integerIn(value, 64, 65536)
    else if (key === "pingHost")
        accepted = typeof value === "string" && value.length > 0 && value.length <= 255
            && !/[\s\x00-\x1f\x7f]/.test(value)

    return accepted ? { accepted: true, key, value } : reject
}

function mergeConfigChanges(serialized, changes, accountingOwner) {
    const raw = parseObject(serialized)
    let changed = false
    for (const key in (changes ?? {})) {
        const accounting = key === "acctState" || key === "appAcctState"
        if (accounting && !accountingOwner) continue
        if (raw[key] !== changes[key]) {
            raw[key] = changes[key]
            changed = true
        }
    }
    return { serialized: JSON.stringify(raw), changed }
}
