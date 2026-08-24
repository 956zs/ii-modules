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
    dayRecord, weeklyReport, weekHourMatrix
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
        coverage: 7, recordedDays: 7, expectedDays: 7,
        days: [
            { k: "2026-07-27", total: 1200, recorded: true },
            { k: "2026-07-28", total: 800, recorded: true },
            { k: "2026-07-29", total: 600, recorded: true },
            { k: "2026-07-30", total: 400, recorded: true },
            { k: "2026-07-31", total: 100, recorded: true },
            { k: "2026-08-01", total: 300, recorded: true },
            { k: "2026-08-02", total: 200, recorded: true }
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
        coverage: 7, recordedDays: 7, expectedDays: 7,
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
    // 07-23..07-26 have no record but fall after tracking began: machine-off
    // days count as real zeros.
    assert.equal(result.current.coverage, 7)
    assert.equal(result.current.recordedDays, 3)
    assert.equal(result.current.expectedDays, 7)
    assert.deepEqual(result.current.days.slice(0, 4), [
        { k: "2026-07-20", total: 100, recorded: true },
        { k: "2026-07-21", total: 200, recorded: true },
        { k: "2026-07-22", total: 300, recorded: true },
        { k: "2026-07-23", total: 0, recorded: false }
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

test("counts tracked-era machine-off days as zeros so comparisons stay available", async () => {
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

    assert.equal(result.current.coverage, 7)
    assert.equal(result.current.recordedDays, 1)
    assert.equal(result.current.expectedDays, 7)
    assert.equal(result.previous.coverage, 7)
    assert.equal(result.previous.recordedDays, 2)
    assert.equal(result.comparisonAvailable, true)
    assert.equal(result.totalDelta, -1200)
    assert.deepEqual(result.current.apps, [
        { n: "browser", s: 1200, previous: 2400, delta: -1200 }
    ])
    assert.deepEqual(result.current.days[1], { k: "2026-07-28", total: 0, recorded: false })
})

test("withholds weekly comparisons when a week has days before tracking began", async () => {
    const logic = await loadLogic()
    const result = plain(logic.weeklyReport({
        todayKey: "2026-08-04",
        todayTotal: 3600,
        todayApps: { browser: 3600 },
        days: [
            { k: "2026-07-29", total: 1200, apps: [{ n: "browser", s: 1200 }] }
        ]
    }))

    assert.equal(result.current.coverage, 5)
    assert.equal(result.current.recordedDays, 1)
    assert.equal(result.previous.coverage, 0)
    assert.equal(result.comparisonAvailable, false)
    assert.equal(result.totalDelta, null)
    assert.deepEqual(result.current.days.slice(0, 4), [
        { k: "2026-07-27", total: null, recorded: false },
        { k: "2026-07-28", total: null, recorded: false },
        { k: "2026-07-29", total: 1200, recorded: true },
        { k: "2026-07-30", total: 0, recorded: false }
    ])
    assert.deepEqual(result.current.apps, [
        { n: "browser", s: 1200, previous: null, delta: null }
    ])
})

test("week hour matrix passes actual per-day values through and zeroes off-days", async () => {
    const logic = await loadLogic()
    const monday = new Array(24).fill(0)
    monday[9] = 1800
    const wednesday = new Array(24).fill(0)
    wednesday[20] = 3600

    const result = plain(logic.weekHourMatrix({
        startKey: "2026-08-10",
        todayKey: "2026-08-24",
        days: [
            { k: "2026-08-10", total: 1800, hours: monday },
            { k: "2026-08-12", total: 3600, hours: wednesday }
        ]
    }))
    assert.equal(result.startKey, "2026-08-10")
    assert.equal(result.endKey, "2026-08-16")
    assert.equal(result.days.length, 7)
    assert.equal(result.recordedDays, 2)
    assert.equal(result.days[0].state, "recorded")
    assert.equal(result.days[0].minutes[9], 30)
    // 2026-08-11 has no record after tracking began: machine off, the row is
    // a REAL all-zero day — never another week's average wearing its date.
    assert.equal(result.days[1].k, "2026-08-11")
    assert.equal(result.days[1].state, "off")
    assert.equal(result.days[1].minutes.reduce((sum, value) => sum + value, 0), 0)
    assert.equal(result.days[2].state, "recorded")
    assert.equal(result.days[2].minutes[20], 60)
    for (let index = 3; index < 7; index++)
        assert.equal(result.days[index].state, "off")
    assert.deepEqual(result.peak, { day: 2, hour: 20, minutes: 60 })
})

test("week hour matrix keeps pre-tracking and hours-less days unknown", async () => {
    const logic = await loadLogic()
    const thursday = new Array(24).fill(0)
    thursday[8] = 900

    const result = plain(logic.weekHourMatrix({
        startKey: "2026-07-27",
        todayKey: "2026-08-24",
        days: [
            { k: "2026-07-29", total: 900, hours: thursday },
            { k: "2026-07-30", total: 5000 },
            { k: "2026-07-31", total: 100, hours: [1, 2] }
        ]
    }))
    // 07-27/07-28 predate the first retained record: unknown, not zero.
    assert.equal(result.days[0].state, "pretracking")
    assert.equal(result.days[1].state, "pretracking")
    assert.equal(result.days[2].state, "recorded")
    assert.equal(result.days[2].minutes[8], 15)
    // Recorded without (valid) hours[24]: distribution unknown, not zero and
    // not fabricated.
    assert.equal(result.days[3].state, "nohours")
    assert.equal(result.days[4].state, "nohours")
    assert.equal(result.days[5].state, "off")
    assert.equal(result.days[6].state, "off")
    assert.equal(result.recordedDays, 1)
    assert.deepEqual(result.peak, { day: 2, hour: 8, minutes: 15 })
})

test("week hour matrix shows today's partial hours and keeps future days unknown", async () => {
    const logic = await loadLogic()
    const monday = new Array(24).fill(0)
    monday[9] = 1800
    const todayHours = new Array(24).fill(0)
    todayHours[8] = 900

    const result = plain(logic.weekHourMatrix({
        startKey: "2026-08-10",
        todayKey: "2026-08-12",
        todayHours,
        todayHoursComplete: true,
        days: [{ k: "2026-08-10", total: 1800, hours: monday }]
    }))
    assert.equal(result.days[0].state, "recorded")
    assert.equal(result.days[1].state, "off")
    assert.equal(result.days[2].state, "recorded")
    assert.equal(result.days[2].minutes[8], 15)
    for (let index = 3; index < 7; index++)
        assert.equal(result.days[index].state, "pretracking")

    const incomplete = plain(logic.weekHourMatrix({
        startKey: "2026-08-10",
        todayKey: "2026-08-12",
        todayHours,
        todayHoursComplete: false,
        days: [{ k: "2026-08-10", total: 1800, hours: monday }]
    }))
    // A mid-day upgrade leaves today's early buckets unknown: not zero.
    assert.equal(incomplete.days[2].state, "nohours")
})

test("week hour matrix rejects invalid input and reports no peak when empty", async () => {
    const logic = await loadLogic()

    const invalid = plain(logic.weekHourMatrix({ startKey: "not-a-day" }))
    assert.deepEqual(invalid, { startKey: "", endKey: "", days: [],
                                recordedDays: 0, peak: null })

    const empty = plain(logic.weekHourMatrix({
        startKey: "2026-07-27", todayKey: "2026-08-24", days: []
    }))
    // No retained records at all: every day is unknown, nothing recorded.
    assert.equal(empty.recordedDays, 0)
    assert.equal(empty.peak, null)
    for (const day of empty.days)
        assert.equal(day.state, "pretracking")
})
