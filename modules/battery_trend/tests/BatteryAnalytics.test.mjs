import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../BatteryAnalytics.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "");
const analytics = {};
vm.createContext(analytics);
vm.runInContext(source, analytics, { filename: "BatteryAnalytics.js" });

const day = 86400;
const now = 40 * day;

function aggregate(t, dis, disSec) {
    return [t, 20, 80, 50, 8, 0, dis, disSec];
}

function accumulator(t, dis, disSec) {
    return {
        t, n: 3, mn: 50, mx: 55, sum: 157,
        wSum: 24, wN: 3, chg: 0, awake: disSec,
        dis, disSec,
    };
}

test("computes normal drain, cycles, sessions, and charge window", () => {
    const stats = analytics.computeStats(now,
        [aggregate(now - 8 * day, 20, 7200), aggregate(now - 2 * day, 10, 3600)],
        [], [], 300, accumulator(now, 5, 1800),
        [["d", now - 2000, now - 1000, 80, 60],
         ["c", now - 900, now - 100, 30, 85]], []);

    assert.deepEqual(JSON.parse(JSON.stringify(stats.today)), {
        dis: 5, rate: 10, avgW: 8, chgH: 0,
    });
    assert.deepEqual(JSON.parse(JSON.stringify(stats.d7)), {
        dis: 15, rate: 10, cycles: 0.15,
    });
    assert.deepEqual(JSON.parse(JSON.stringify(stats.d30)), {
        dis: 35, rate: 10, cycles: 0.35,
    });
    assert.equal(stats.dod, 20);
    assert.equal(stats.chargeFrom, 30);
    assert.equal(stats.chargeTo, 85);
});

test("returns explicit unavailable values for empty and null input", () => {
    const stats = analytics.computeStats(now,
        null, null, null, null, null, null, null);

    assert.deepEqual(JSON.parse(JSON.stringify(stats.today)), {
        dis: 0, rate: 0, avgW: 0, chgH: 0,
    });
    assert.equal(stats.d7.dis, 0);
    assert.equal(stats.d30.cycles, 0);
    assert.equal(stats.dod, -1);
    assert.equal(stats.chargeFrom, -1);
});

test("uses an inclusive exact time-window boundary", () => {
    const days = {
        before: { t: now - 7 * day - 1, dis: 99, disSec: 3600 },
        boundary: { t: now - 7 * day, dis: 7, disSec: 3600 },
    };

    assert.deepEqual(JSON.parse(JSON.stringify(
        analytics.windowStats(days, now, 7 * day))), {
        dis: 7, rate: 7, cycles: 0.07,
    });
    assert.equal(analytics.windowStats(days, now, 30 * day).dis, 106);
});

test("daily data overrides same-day hourly data without double counting", () => {
    const dayStart = now - 2 * day;
    const stats = analytics.computeStats(now,
        [aggregate(dayStart, 40, 7200)],
        [aggregate(dayStart + 3600, 10, 1800), aggregate(dayStart + 7200, 5, 1800)],
        [], 300, null, [], []);

    assert.equal(stats.d7.dis, 40);
    assert.equal(stats.d7.rate, 20);
});

test("hourly and raw data fill days that have no daily bucket", () => {
    const hourlyDay = now - 2 * day;
    const rawDay = now - day;
    const stats = analytics.computeStats(now, [],
        [aggregate(hourlyDay, 4, 1800)],
        [[rawDay, 80, 8, 0], [rawDay + 60, 79, 8, 0], [rawDay + 120, 78, 8, 0]],
        300, null, [], []);

    assert.equal(stats.d7.dis, 6);
    assert.equal(stats.d7.rate, 11.3);
    assert.equal(stats.d7.cycles, 0.06);
});

test("ignores malformed records and never emits NaN", () => {
    const stats = analytics.computeStats(now,
        [null, [], ["bad", 0, 0, 0, 0, 0, "oops", null]],
        [[now - day, 0, 0, 0, 0, 0, 4, 1800]],
        [["bad"], [now - 60, "bad", 4, 0], [now, 50, 4, 0]],
        300, { t: now, n: "bad", dis: "bad", disSec: -1 },
        [null, ["d", "bad", 0, 90, 10], ["d", now - 100, now, 90, 89]],
        [[now - day, "bad", -1]]);

    assert.equal(stats.d7.dis, 4);
    assert.equal(stats.d7.rate, 8);
    assert.equal(stats.dod, -1);
    assert.equal(stats.hNow, -1);
    for (const value of [stats.today.rate, stats.d7.rate, stats.d30.cycles])
        assert.equal(Number.isFinite(value), true);
});
