import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const moduleRoot = new URL("../", import.meta.url)

async function read(name) {
    return readFile(new URL(name, moduleRoot), "utf8")
}

test("details panel browses the retained date range with accessible controls", async () => {
    const source = await read("DetailsPanel.qml")

    assert.match(source, /property string selectedDayKey:/)
    assert.match(source, /shiftDayKey\(root\.logic\.curDayKey, -29\)/)
    assert.match(source, /function moveSelectedDay\(delta\)/)
    assert.match(source, /Accessible\.name: Translation\.tr\("Previous day"\)/)
    assert.match(source, /Accessible\.name: Translation\.tr\("Next day"\)/)
    assert.match(source, /onClicked: root\.selectedDayKey = root\.logic\.curDayKey/)
})

test("selected day drives totals, app ranking, and AI summary", async () => {
    const source = await read("DetailsPanel.qml")

    assert.match(source, /HistoryLogic\.dayRecord\(/)
    assert.match(source, /readonly property list<var> ranking: root\.selectedDay\.apps\.slice\(0, 9\)/)
    assert.match(source, /text: fmt\.dur\(root\.selectedDay\.total\)/)
    assert.match(source, /visible: !root\.selectedIsToday && !root\.selectedDay\.hasData/)
    assert.match(source, /Translation\.tr\("No record for this day"\)/)
    assert.match(source, /visible: root\.selectedIsToday && root\.yesterdayTotal >= 0/)
    assert.match(source, /text: fmt\.dur\(root\.selectedDay\.aiU\)/)
    assert.match(source, /root\.selectedDay\.aiP/)
    assert.match(source, /root\.selectedDay\.aiS/)
})

test("hourly detail and live agent status remain today-only", async () => {
    const source = await read("DetailsPanel.qml")

    assert.match(source, /\/\/ Today by hour\s+ColumnLayout \{\s+visible: root\.selectedTab === "daily" && root\.selectedIsToday/)
    assert.match(source, /if \(root\.selectedIsToday && root\.logic\.aiActiveNow > 0\)/)
    assert.match(source, /visible: root\.selectedIsToday\s+Layout\.fillWidth: true\s+Layout\.topMargin: 2\s+values: root\.t7\.map\(d => d\.ai\)/)
})

test("daily and trends tabs separate date detail from aggregate analysis", async () => {
    const source = await read("DetailsPanel.qml")

    assert.match(source, /property string selectedTab: "daily"/)
    assert.match(source, /key: "daily", label: Translation\.tr\("Daily"\)/)
    assert.match(source, /key: "trends", label: Translation\.tr\("Trends"\)/)
    assert.match(source, /visible: root\.selectedTab === "daily"/)
    assert.match(source, /visible: root\.selectedTab === "trends"/)
    assert.match(source, /flick\.contentY = 0/)
    assert.match(source, /color: tabButton\.toggled\s+\? Appearance\.colors\.colOnPrimary/)
})

test("trends use complete-day coverage, missing-value masks, and hourly heatmap", async () => {
    const source = await read("DetailsPanel.qml")

    assert.match(source, /HistoryLogic\.periodSummary\(root\.logic\.curDayKey, root\.logic\.days, 7\)/)
    assert.match(source, /HistoryLogic\.hourHeatmap\(root\.logic\.curDayKey, root\.logic\.days, 28\)/)
    assert.match(source, /root\.period7\.current\.coverage/)
    assert.match(source, /present: root\.period7\.current\.days\.map\(day => day\.total !== null\)/)
    assert.match(source, /referenceValue: root\.period7\.current\.coverage > 0/)
    assert.match(source, /HourHeatmap \{/)
    assert.match(source, /root\.heatmap28\.coverage/)
    assert.match(source, /present: root\.t30\.map\(d => d\.total !== null\)/)
})

test("hour heatmap is keyboard-readable and uses a Material sequential scale", async () => {
    const source = await read("HourHeatmap.qml")

    assert.match(source, /activeFocusOnTab: true/)
    assert.match(source, /Qt\.Key_Left/)
    assert.match(source, /Qt\.Key_Right/)
    assert.match(source, /Qt\.Key_Up/)
    assert.match(source, /Qt\.Key_Down/)
    assert.match(source, /Appearance\.colors\.colPrimary/)
    assert.match(source, /property color primaryColor:/)
    assert.match(source, /property color surfaceColor:/)
    assert.match(source, /function onPrimaryColorChanged\(\) \{ canvas\.requestPaint\(\) \}/)
    assert.match(source, /function onSurfaceColorChanged\(\) \{ canvas\.requestPaint\(\) \}/)
    assert.match(source, /Accessible\.name: readout\.text/)
    assert.match(source, /function maximumMinutes\(\)/)
    assert.doesNotMatch(source, /\.flat\(\)/)
    assert.match(source, /property var valueLabel:/)
    assert.match(source, /model: \[0\.2, 0\.45, 0\.7, 1\]/)
})

test("chart presence masks distinguish unknown dates from recorded zeroes", async () => {
    const [columns, line] = await Promise.all([read("ColumnChart.qml"), read("LineChart.qml")])

    assert.match(columns, /property var present: \[\]/)
    assert.match(columns, /root\.present\.length === 0 \|\| root\.present\[i\] === true/)
    assert.match(columns, /property real referenceValue: -1/)
    assert.match(columns, /ctx\.setLineDash\(\[4, 3\]\)/)
    assert.match(line, /property var present: \[\]/)
    assert.match(line, /function observed\(index\)/)
    assert.match(line, /if \(!root\.observed\(i\)\)/)
    assert.match(line, /neutral baseline tick/)
})

test("all historical folds persist complete hourly buckets while old records stay optional", async () => {
    const [logic, config] = await Promise.all([read("ScreentimeLogic.qml"), read("ConfigLoader.qml")])

    assert.match(logic, /foldedDay\(root\.curDayKey, root\.todayApps,/)
    assert.match(logic, /root\.hoursComplete \? root\.hours : undefined/)
    assert.match(logic, /property bool hoursComplete: true/)
    assert.match(logic, /hoursComplete: root\.hoursComplete/)
    assert.match(logic, /day\.hoursComplete !== false/)
    assert.match(logic, /if \(root\.curDayKey === ""\) return/)
    assert.doesNotMatch(logic, /root\.todayTotal <= 0/)
    assert.match(logic, /foldedDay\(day\.k, day\.apps, day\.hours,/)
    assert.match(logic, /function foldedDay\(key, appsMap, hourValues, aiU, aiS, aiP\)/)
    assert.match(logic, /folded\.hours = hours/)
    assert.match(config, /hours\?:\[24\]/)
    assert.match(config, /hoursComplete:bool/)
    assert.match(config, /mid-day upgrade/)
    assert.match(config, /records written before v1\.3/)
})

test("rollover and trend helpers keep historical time buckets honest", async () => {
    const logic = await read("ScreentimeLogic.qml")

    assert.match(logic, /const rolledOver = root\.curDayKey !== nowDayKey/)
    assert.match(logic, /const creditedHour = rolledOver \? now\.getHours\(\) : startHour/)
    assert.match(logic, /typeof total === "number"/)
    assert.match(logic, /Number\.isFinite\(total\) && total >= 0 \? total : null/)
    assert.doesNotMatch(logic, /Number\(rec\.total\) \|\| 0/)
})

test("history helper stays compatible with the Quickshell JavaScript parser", async () => {
    const source = await read("HistoryLogic.js")

    assert.doesNotMatch(source, /\{\s*\.\.\./)
})

test("history and trends are documented, translated, and versioned as additive", async () => {
    const [readme, zhTw, zhCn, manifestText] = await Promise.all([
        read("README.md"), read("translations/zh_TW.json"),
        read("translations/zh_CN.json"), read("module.json")
    ])
    const manifest = JSON.parse(manifestText)

    assert.match(readme, /詳情面板分成「每日／趨勢」兩頁/)
    assert.match(readme, /星期×時段熱力圖/)
    assert.match(readme, /N\/28/)
    for (const text of [zhTw, zhCn]) {
        const translation = JSON.parse(text)
        assert.ok(translation["Previous day"])
        assert.ok(translation["Next day"])
        assert.ok(translation["Back to today"])
        assert.ok(translation["Apps on this day"])
        assert.ok(translation["No record for this day"])
        assert.ok(translation["Daily"])
        assert.ok(translation["Trends"])
        assert.ok(translation["Typical hours"])
        assert.ok(translation["%1 of 28 days have hourly detail"])
    }
    assert.equal(manifest.version, "1.3.1")
    assert.match(manifest.description.en_US, /Daily and Trends tabs/)
    assert.match(manifest.description.en_US, /hourly heatmap/)
})
