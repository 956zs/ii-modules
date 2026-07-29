import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

async function loadLogic() {
    const source = (await readFile(new URL("../HistoryLogic.js", import.meta.url), "utf8"))
        .replace(/^\.pragma library\s*/, "")
    const context = vm.createContext({ Date })
    vm.runInContext(`${source}\nglobalThis.api = { shiftDayKey, dayRecord, periodSummary, hourHeatmap }`, context)
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

test("summarizes complete recorded days without treating missing dates as zero", async () => {
    const logic = await loadLogic()
    const days = [
        { k: "2026-07-14", total: 100 },
        { k: "2026-07-15", total: 200 },
        { k: "2026-07-21", total: 3600 },
        { k: "2026-07-23", total: 7200 },
        { k: "2026-07-23", total: 10800 },
        { k: "2026-07-27", total: "bad" },
        { k: "2026-07-28", total: null },
        { k: "2026-07-29", total: 99999 }
    ]

    const result = plain(logic.periodSummary("2026-07-29", days, 7))
    assert.deepEqual(result.current, {
        startKey: "2026-07-22", endKey: "2026-07-28", average: 10800,
        coverage: 1, span: 7,
        days: [
            { k: "2026-07-22", total: null }, { k: "2026-07-23", total: 10800 },
            { k: "2026-07-24", total: null }, { k: "2026-07-25", total: null },
            { k: "2026-07-26", total: null }, { k: "2026-07-27", total: null },
            { k: "2026-07-28", total: null }
        ]
    })
    assert.equal(result.previous.average, 1900)
    assert.equal(result.previous.coverage, 2)
    assert.equal(result.delta, 8900)
})

test("period summary handles invalid inputs and zero-valued recorded days", async () => {
    const logic = await loadLogic()

    assert.deepEqual(plain(logic.periodSummary("bad", [], 7)), {
        current: { startKey: "", endKey: "", average: 0, coverage: 0, span: 7, days: [] },
        previous: { startKey: "", endKey: "", average: 0, coverage: 0, span: 7, days: [] },
        delta: null
    })
    const result = plain(logic.periodSummary("2026-07-29", [{ k: "2026-07-28", total: 0 }], 1))
    assert.equal(result.current.coverage, 1)
    assert.equal(result.current.average, 0)
    assert.equal(result.delta, null)
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
