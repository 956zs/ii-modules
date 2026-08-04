import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

async function loadLogic() {
    const source = (await readFile(new URL("../HistoryLogic.js", import.meta.url), "utf8"))
        .replace(/^\.pragma library\s*/, "")
    const context = vm.createContext({ Date })
    vm.runInContext(`${source}
globalThis.api = {
    shiftDayKey, weekStartKey, previousCompleteWeekStartKey,
    dayRecord, weeklyReport, hourHeatmap
}`, context)
    return context.api
}

function plain(value) {
    return JSON.parse(JSON.stringify(value))
}

test("moves across month and leap-day boundaries", async () => {
    const logic = await loadLogic()

    assert.equal(logic.shiftDayKey("2026-03-01", -1), "2026-02-28")
    assert.equal(logic.shiftDayKey("2024-03-01", -1), "2024-02-29")
    assert.equal(logic.shiftDayKey("2026-12-31", 1), "2027-01-01")
})

test("rejects invalid dates and offsets", async () => {
    const logic = await loadLogic()

    assert.equal(logic.shiftDayKey("", -1), "")
    assert.equal(logic.shiftDayKey("2026-02-30", -1), "")
    assert.equal(logic.shiftDayKey("2026-07-29", 0.5), "")
})

test("normalizes today's live totals and ranking", async () => {
    const logic = await loadLogic()
    const result = plain(logic.dayRecord(
        "2026-07-29", "2026-07-29", 5400,
        { browser: 1800, editor: 3600, broken: -3 }, 900, 1200, 2, []))

    assert.deepEqual(result, {
        k: "2026-07-29", total: 5400,
        apps: [{ n: "editor", s: 3600 }, { n: "browser", s: 1800 }],
        aiU: 900, aiS: 1200, aiP: 2, isToday: true, hasData: true
    })
})

test("reads a persisted historical day and handles empty or malformed data", async () => {
    const logic = await loadLogic()
    const days = [{
        k: "2026-07-28", total: 1, apps: [{ n: "stale", s: 1 }]
    }, {
        k: "2026-07-28", total: 7200,
        apps: [{ n: "browser", s: 4800 }, null, { n: "bad", s: "nope" }],
        aiU: 600, aiS: 600, aiP: 1
    }]

    assert.deepEqual(plain(logic.dayRecord("2026-07-28", "2026-07-29", 0, null, 0, 0, 0, days)), {
        k: "2026-07-28", total: 7200, apps: [{ n: "browser", s: 4800 }],
        aiU: 600, aiS: 600, aiP: 1, isToday: false, hasData: true
    })
    assert.deepEqual(plain(logic.dayRecord("2026-07-01", "2026-07-29", 0, null, 0, 0, 0, null)), {
        k: "2026-07-01", total: 0, apps: [], aiU: 0, aiS: 0, aiP: 0,
        isToday: false, hasData: false
    })
})

test("defaults to the last complete ISO week and compares full weeks", async () => {
    const logic = await loadLogic()
    const days = [
        { k: "2026-07-20", total: 100, apps: [{ n: "browser", s: 100 }] },
        { k: "2026-07-21", total: 200, apps: [{ n: "chat", s: 200 }] },
        { k: "2026-07-22", total: 300, apps: [{ n: "terminal", s: 300 }] },
        { k: "2026-07-23", total: 400, apps: [{ n: "editor", s: 400 }] },
        { k: "2026-07-24", total: 500, apps: [{ n: "browser", s: 500 }] },
        { k: "2026-07-25", total: 600, apps: [{ n: "chat", s: 600 }] },
        { k: "2026-07-26", total: 700, apps: [{ n: "browser", s: 700 }] },
        { k: "2026-07-27", total: 1200,
          apps: [{ n: "browser", s: 1000 }, { n: "editor", s: 200 }] },
        { k: "2026-07-28", total: 800,
          apps: [{ n: "browser", s: 500 }, { n: "chat", s: 300 }] },
        { k: "2026-07-29", total: 600, apps: [{ n: "terminal", s: 600 }] },
        { k: "2026-07-30", total: 400, apps: [{ n: "browser", s: 400 }] },
        { k: "2026-07-31", total: 100, apps: [{ n: "editor", s: 100 }] },
        { k: "2026-08-01", total: 300, apps: [{ n: "chat", s: 300 }] },
        { k: "2026-08-02", total: 200, apps: [{ n: "terminal", s: 200 }] },
        { k: "2026-08-03", total: 99999, apps: [{ n: "browser", s: 99999 }] }
    ]

    const result = plain(logic.weeklyReport({
        todayKey: "2026-08-04", todayTotal: 88888,
        todayApps: { editor: 88888 },
        days
    }))

    assert.deepEqual(result.info, {
        year: 2026, week: 31, startKey: "2026-07-27", endKey: "2026-08-02"
    })
    assert.deepEqual(result.current, {
        startKey: "2026-07-27", endKey: "2026-08-02", total: 3600,
        coverage: 7, expectedDays: 7,
        days: [
            { k: "2026-07-27", total: 1200 }, { k: "2026-07-28", total: 800 },
            { k: "2026-07-29", total: 600 }, { k: "2026-07-30", total: 400 },
            { k: "2026-07-31", total: 100 }, { k: "2026-08-01", total: 300 },
            { k: "2026-08-02", total: 200 }
        ],
        apps: [
            { n: "browser", s: 1900, previous: 1300, delta: 600 },
            { n: "terminal", s: 800, previous: 300, delta: 500 },
            { n: "chat", s: 600, previous: 800, delta: -200 },
            { n: "editor", s: 300, previous: 400, delta: -100 }
        ]
    })
    assert.deepEqual(result.previous, {
        startKey: "2026-07-20", endKey: "2026-07-26", total: 2800,
        coverage: 7, expectedDays: 7,
        apps: [
            { n: "browser", s: 1300 }, { n: "chat", s: 800 },
            { n: "editor", s: 400 }, { n: "terminal", s: 300 }
        ]
    })
    assert.equal(result.comparisonAvailable, true)
    assert.equal(result.totalDelta, 800)
    assert.equal(result.lastCompleteStartKey, "2026-07-27")
})

test("can build an explicitly selected historical ISO week", async () => {
    const logic = await loadLogic()
    const result = plain(logic.weeklyReport({
        todayKey: "2026-08-04", todayTotal: 0, todayApps: {},
        weekStartKey: "2026-07-22",
        days: [
            { k: "2026-07-20", total: 100, apps: [{ n: "browser", s: 100 }] },
            { k: "2026-07-21", total: 200, apps: [{ n: "browser", s: 200 }] },
            { k: "2026-07-22", total: 300, apps: [{ n: "editor", s: 300 }] }
        ]
    }))

    assert.deepEqual(result.info, {
        year: 2026, week: 30, startKey: "2026-07-20", endKey: "2026-07-26"
    })
    assert.equal(result.current.coverage, 3)
    assert.equal(result.current.expectedDays, 7)
    assert.deepEqual(result.current.days.slice(0, 3), [
        { k: "2026-07-20", total: 100 },
        { k: "2026-07-21", total: 200 },
        { k: "2026-07-22", total: 300 }
    ])
})

test("uses the ISO week-year at calendar year boundaries", async () => {
    const logic = await loadLogic()
    const yearEnd = plain(logic.weeklyReport({
        todayKey: "2021-01-01", todayTotal: 0, todayApps: {}, days: []
    }))
    const firstMonday = plain(logic.weeklyReport({
        todayKey: "2021-01-04", todayTotal: 0, todayApps: {}, days: []
    }))

    assert.deepEqual(yearEnd.info, {
        year: 2020, week: 52, startKey: "2020-12-21", endKey: "2020-12-27"
    })
    assert.equal(yearEnd.current.expectedDays, 7)
    assert.deepEqual(firstMonday.info, {
        year: 2020, week: 53, startKey: "2020-12-28", endKey: "2021-01-03"
    })
})

test("withholds weekly comparisons when either full-week period has gaps", async () => {
    const logic = await loadLogic()
    const result = plain(logic.weeklyReport({
        todayKey: "2026-08-04",
        todayTotal: 3600,
        todayApps: { browser: 3600 },
        days: [
            { k: "2026-07-20", total: 1200, apps: [{ n: "browser", s: 1200 }] },
            { k: "2026-07-21", total: 1200, apps: [{ n: "browser", s: 1200 }] },
            { k: "2026-07-27", total: 1200, apps: [{ n: "browser", s: 1200 }] }
        ]
    }))

    assert.equal(result.current.coverage, 1)
    assert.equal(result.current.expectedDays, 7)
    assert.equal(result.previous.coverage, 2)
    assert.equal(result.comparisonAvailable, false)
    assert.equal(result.totalDelta, null)
    assert.deepEqual(result.current.apps, [
        { n: "browser", s: 1200, previous: null, delta: null }
    ])
})

test("builds a weekday by hour heatmap from complete hourly records only", async () => {
    const logic = await loadLogic()
    const mondayA = new Array(24).fill(0)
    mondayA[9] = 1800
    const mondayB = new Array(24).fill(0)
    mondayB[9] = 3600
    const tuesday = new Array(24).fill(0)
    tuesday[18] = 900
    const days = [
        { k: "2026-07-06", total: 1800, hours: mondayA },
        { k: "2026-07-13", total: 3600, hours: mondayB },
        { k: "2026-07-14", total: 900, hours: tuesday },
        { k: "2026-07-15", total: 100, hours: [1, 2] },
        { k: "2026-06-01", total: 999, hours: new Array(24).fill(999) },
        { k: "2026-07-29", total: 999, hours: new Array(24).fill(999) }
    ]

    const result = plain(logic.hourHeatmap("2026-07-29", days, 28))
    assert.equal(result.coverage, 3)
    assert.equal(result.startKey, "2026-07-01")
    assert.equal(result.endKey, "2026-07-28")
    assert.equal(result.values.length, 7)
    assert.equal(result.values[0][9], 45)
    assert.equal(result.values[1][18], 15)
    assert.deepEqual(result.peak, { dow: 0, hour: 9, minutes: 45 })
})

test("heatmap rejects malformed hourly values and reports no peak when empty", async () => {
    const logic = await loadLogic()
    const malformed = new Array(24).fill(0)
    malformed[4] = -10
    malformed[5] = "bad"

    const result = plain(logic.hourHeatmap("2026-07-29", [
        { k: "2026-07-28", hours: malformed },
        { k: "not-a-day", hours: new Array(24).fill(60) }
    ], 28))
    assert.equal(result.coverage, 0)
    assert.equal(result.values[0].length, 24)
    assert.equal(result.values.flat().reduce((sum, value) => sum + value, 0), 0)
    assert.equal(result.peak, null)
})
