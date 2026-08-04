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
    assert.match(source, /retainedHistoryOffsetDays: root\.retainedHistoryDays - 1/)
    assert.match(source, /root\.logic\.curDayKey, -root\.retainedHistoryOffsetDays/)
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

test("daily and weekly tabs separate date detail from calendar-week analysis", async () => {
    const source = await read("DetailsPanel.qml")

    assert.match(source, /property string selectedTab: "daily"/)
    assert.match(source, /key: "daily", label: Translation\.tr\("Daily"\)/)
    assert.match(source, /key: "weekly", label: Translation\.tr\("Weekly"\)/)
    assert.match(source, /visible: root\.selectedTab === "daily"/)
    assert.match(source, /visible: root\.selectedTab === "weekly"/)
    assert.match(source, /flick\.contentY = 0/)
    assert.match(source, /color: tabButton\.toggled\s+\? Appearance\.colors\.colOnPrimary/)
})

test("weekly report defaults to the last complete week and can browse history", async () => {
    const [panel, report] = await Promise.all([
        read("DetailsPanel.qml"), read("WeeklyReport.qml")
    ])

    assert.match(panel, /property string selectedWeekStartKey:/)
    assert.match(panel, /previousCompleteWeekStartKey\(root\.logic\.curDayKey\)/)
    assert.match(panel, /function moveSelectedWeek\(delta\)/)
    assert.match(panel, /function resetSelectedWeek\(\)/)
    assert.match(panel, /Accessible\.name: Translation\.tr\("Previous week"\)/)
    assert.match(panel, /Accessible\.name: Translation\.tr\("Next week"\)/)
    assert.match(panel, /Translation\.tr\("Back to last complete week"\)/)
    assert.match(panel, /weekStartKey: root\.selectedWeekStartKey/)
    assert.match(panel, /HistoryLogic\.weeklyReport\(\{/)
    assert.match(panel, /todayKey: root\.logic\.curDayKey/)
    assert.match(panel, /Loader \{/)
    assert.match(panel, /active: root\.selectedTab === "weekly"/)
    assert.match(panel, /sourceComponent: WeeklyReport \{/)
    assert.match(report, /import qs\.services/)
    assert.match(report, /Translation\.tr\("Week %1 of %2"\)/)
    assert.match(report, /text: fmt\.dur\(root\.report\.current\.total\)/)
    assert.match(report, /root\.report\.current\.coverage/)
    assert.match(report, /root\.report\.current\.expectedDays/)
    assert.match(report, /present: root\.report\.current\.days\.map\(day => day\.total !== null\)/)
    assert.match(report, /Translation\.tr\("vs previous week"\)/)
})

test("weekly report identifies top apps and compares each with last week", async () => {
    const source = await read("WeeklyReport.qml")

    assert.match(source, /root\.report\.current\.apps\.slice\(0, root\.maximumRankedApps\)/)
    assert.match(source, /Translation\.tr\("Most used app"\)/)
    assert.match(source, /fmt\.appName\(root\.topApp\.n\)/)
    assert.match(source, /fmt\.dur\(root\.topApp\.s\)/)
    assert.match(source, /Translation\.tr\("Apps in selected week"\)/)
    assert.match(source, /appRow\.modelData\.delta/)
    assert.match(source, /Translation\.tr\("Comparison unavailable"\)/)
    assert.match(source, /readonly property var topApp:/)
    assert.doesNotMatch(source, /root\.ranking\[0\]\.(?:n|s|delta)/)
})

test("weekly report retains broader hourly and 30-day context", async () => {
    const source = await read("WeeklyReport.qml")

    assert.match(source, /HourHeatmap \{/)
    assert.match(source, /root\.heatmap\.coverage/)
    assert.match(source, /present: root\.days30\.map\(day => day\.total !== null\)/)
    assert.ok(source.indexOf('Translation.tr("Selected week")')
        < source.indexOf('Translation.tr("Typical hours")'))
    assert.ok(source.indexOf('Translation.tr("Typical hours")')
        < source.indexOf('Translation.tr("Most used app")'))
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

test("daily and calendar-week reports are documented, translated, and versioned as additive", async () => {
    const [readme, zhTw, zhCn, manifestText] = await Promise.all([
        read("README.md"), read("translations/zh_TW.json"),
        read("translations/zh_CN.json"), read("module.json")
    ])
    const manifest = JSON.parse(manifestText)

    assert.match(readme, /詳情面板分成「每日／週報」兩頁/)
    assert.match(readme, /ISO 8601/)
    assert.match(readme, /上一個完整週/)
    assert.match(readme, /完整週對完整週/)
    assert.match(readme, /選取週應用排行/)
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
        assert.ok(translation["Weekly"])
        assert.ok(translation["Previous week"])
        assert.ok(translation["Next week"])
        assert.ok(translation["Back to last complete week"])
        assert.ok(translation["Last complete week"])
        assert.ok(translation["Week %1 of %2"])
        assert.ok(translation["Most used app"])
        assert.ok(translation["Apps in selected week"])
        assert.ok(translation["vs previous week"])
        assert.ok(translation["Typical hours"])
        assert.ok(translation["%1 of 28 days have hourly detail"])
    }
    assert.equal(manifest.version, "1.5.0")
    assert.match(manifest.description.en_US, /Daily and Weekly tabs/)
    assert.match(manifest.description.en_US, /last complete ISO calendar week/)
    assert.match(manifest.description.en_US, /per-app comparison/)
    assert.match(manifest.description.en_US, /hourly heatmap/)
})
