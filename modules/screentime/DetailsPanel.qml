import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.screentime
import "HistoryLogic.js" as HistoryLogic

/*
 * Detail view, opened via IPC (sidebar tile / bar click). A bar-adjacent
 * floating window following the bar's position, closing on click-outside or
 * Esc — same frame idiom as indicator_tools' PanelShell.
 *
 * Reads the live ScreentimeLogic instance (same window-slot scope), so
 * unlike the bar widget nothing here is flush-stale.
 */
PanelWindow {
    id: root
    required property var logic
    property real panelWidth: 380
    property string selectedDayKey: root.logic.curDayKey
    property string selectedWeekStartKey: HistoryLogic.previousCompleteWeekStartKey(root.logic.curDayKey)
    property string selectedTab: "daily"

    readonly property int retainedHistoryDays: 30
    readonly property int hourHeatmapSpanDays: 28
    readonly property int daysPerWeek: 7
    readonly property int nextDayOffsetDays: 1
    readonly property int retainedHistoryOffsetDays: root.retainedHistoryDays - 1
    readonly property int weekEndOffsetDays: root.daysPerWeek - 1
    readonly property string earliestDayKey: HistoryLogic.shiftDayKey(
        root.logic.curDayKey, -root.retainedHistoryOffsetDays)
    readonly property string earliestWeekStartKey: HistoryLogic.weekStartKey(root.earliestDayKey)
    readonly property string latestCompleteWeekStartKey: HistoryLogic.previousCompleteWeekStartKey(
        root.logic.curDayKey)
    readonly property bool selectedIsToday: root.selectedDayKey === root.logic.curDayKey
    readonly property bool selectedWeekIsLatest: root.selectedWeekStartKey
        === root.latestCompleteWeekStartKey
    readonly property bool canGoPrevious: root.selectedDayKey > root.earliestDayKey
    readonly property bool canGoNext: root.selectedDayKey < root.logic.curDayKey
    readonly property bool canGoPreviousWeek: root.selectedWeekStartKey > root.earliestWeekStartKey
    readonly property bool canGoNextWeek: root.selectedWeekStartKey < root.latestCompleteWeekStartKey

    visible: false
    function toggle() {
        if (!root.visible) {
            root.selectedDayKey = root.logic.curDayKey
            root.resetSelectedWeek()
        }
        root.visible = !root.visible
    }

    function moveSelectedDay(delta) {
        const candidate = HistoryLogic.shiftDayKey(root.selectedDayKey, delta)
        if (candidate !== "" && candidate >= root.earliestDayKey && candidate <= root.logic.curDayKey)
            root.selectedDayKey = candidate
    }

    function moveSelectedWeek(delta) {
        const candidate = HistoryLogic.shiftDayKey(
            root.selectedWeekStartKey, delta * root.daysPerWeek)
        if (candidate !== "" && candidate >= root.earliestWeekStartKey
                && candidate <= root.latestCompleteWeekStartKey)
            root.selectedWeekStartKey = candidate
    }

    function resetSelectedWeek() {
        root.selectedWeekStartKey = root.latestCompleteWeekStartKey
    }

    onLatestCompleteWeekStartKeyChanged: {
        if (root.selectedWeekStartKey === ""
                || root.selectedWeekStartKey > root.latestCompleteWeekStartKey)
            root.resetSelectedWeek()
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:iimp-screentime"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors.top: !Config.options.bar.vertical && !Config.options.bar.bottom
    anchors.bottom: Config.options.bar.bottom || Config.options.bar.vertical
    anchors.left: Config.options.bar.vertical && !Config.options.bar.bottom
    anchors.right: !Config.options.bar.vertical || Config.options.bar.bottom
    margins {
        top: Appearance.sizes.barHeight
        bottom: Config.options.bar.vertical ? 8 : Appearance.sizes.barHeight
        left: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 8
        right: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 8
    }

    implicitWidth: root.panelWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: background.implicitHeight + Appearance.sizes.elevationMargin * 2

    // Live data, re-derived after every accounting event.
    readonly property var selectedDay: {
        root.logic.revision
        return HistoryLogic.dayRecord(
            root.selectedDayKey, root.logic.curDayKey,
            root.logic.todayTotal, root.logic.todayApps,
            root.logic.aiUnion, root.logic.aiSum, root.logic.aiPeak,
            root.logic.days)
    }
    readonly property list<var> ranking: root.selectedDay.apps.slice(0, 9)
    readonly property real topSeconds: root.ranking.length > 0 ? root.ranking[0].s : 0
    readonly property list<real> hourValues: {
        root.logic.revision
        return root.logic.hours.map(v => Number(v) || 0)
    }
    readonly property list<var> t7: {
        root.logic.revision
        return root.logic.trend7()
    }
    readonly property list<var> t30: {
        root.logic.revision
        return root.logic.trend30()
    }
    readonly property real yesterdayTotal: {
        root.logic.revision
        const d = new Date()
        d.setDate(d.getDate() - 1)
        const rec = root.logic.days.find(x => x.k === root.logic.dayKeyOf(d))
        return rec ? (Number(rec.total) || 0) : -1
    }
    readonly property real delta: root.logic.todayTotal - root.yesterdayTotal
    readonly property int curHour: {
        root.logic.revision
        return new Date().getHours()
    }
    readonly property var weekReport: {
        root.logic.revision
        return HistoryLogic.weeklyReport({
            todayKey: root.logic.curDayKey,
            todayTotal: root.logic.todayTotal,
            todayApps: root.logic.todayApps,
            weekStartKey: root.selectedWeekStartKey,
            days: root.logic.days
        })
    }
    readonly property var heatmap28: {
        root.logic.revision
        const anchorKey = HistoryLogic.shiftDayKey(
            root.weekReport.current.endKey, root.nextDayOffsetDays)
        return HistoryLogic.hourHeatmap(anchorKey, root.logic.days, root.hourHeatmapSpanDays)
    }
    // AI dimension: the selected day's persisted summary, plus live status on
    // today. Past days never inherit the current process status.
    readonly property bool aiAny: root.selectedDay.aiU >= 1
        || (root.selectedIsToday && root.logic.aiSessionsNow > 0)
    readonly property real aiAvg7: root.t7.reduce((acc, d) => acc + d.ai, 0) / 7
    readonly property string aiCaption: {
        const bits = []
        if (root.selectedIsToday && root.logic.aiActiveNow > 0)
            bits.push(Translation.tr("%1 working now").arg(root.logic.aiActiveNow))
        if (root.selectedDay.aiP > 1) {
            bits.push(Translation.tr("peak %1 parallel").arg(root.selectedDay.aiP))
            bits.push(Translation.tr("sum %1").arg(fmt.dur(root.selectedDay.aiS)))
        }
        return bits.join(" · ")
    }

    function mdLabel(key) {
        const p = key.split("-")
        return p.length === 3 ? `${Number(p[1])}/${Number(p[2])}` : key
    }

    function selectedDayLabel() {
        if (root.selectedIsToday)
            return Translation.tr("Today")
        const p = root.selectedDayKey.split("-")
        if (p.length !== 3)
            return root.selectedDayKey
        const date = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]), 12)
        return `${Number(p[1])}/${Number(p[2])} · ${fmt.weekdayLetter(date.getDay())}`
    }

    function weekRangeLabel(startKey) {
        const endKey = HistoryLogic.shiftDayKey(startKey, root.weekEndOffsetDays)
        return `${root.mdLabel(startKey)}-${root.mdLabel(endKey)}`
    }

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.visible = false
    }

    Item {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.visible = false

        Format { id: fmt }

        StyledRectangularShadow {
            target: background
        }

        Rectangle {
            id: background
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            implicitHeight: Math.min(
                flick.contentHeight + 16 * 2,
                (root.screen?.height ?? 900) - Appearance.sizes.barHeight * 2 - 32)
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 16
                clip: true
                contentHeight: col.implicitHeight
                contentWidth: width
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: col
                    width: flick.width
                    spacing: 14

                    // Header + hero stat
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        MaterialSymbol {
                            text: "timelapse"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            text: Translation.tr("Screen time")
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [{ key: "daily", label: Translation.tr("Daily") },
                                    { key: "weekly", label: Translation.tr("Weekly") }]
                            delegate: RippleButton {
                                id: tabButton
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.full
                                toggled: root.selectedTab === modelData.key
                                onClicked: {
                                    root.selectedTab = modelData.key
                                    flick.contentY = 0
                                }
                                Accessible.name: modelData.label
                                contentItem: StyledText {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: tabButton.toggled
                                        ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                    text: tabButton.modelData.label
                                }
                            }
                        }
                    }

                    // Browse the retained 30-day history one calendar day at a
                    // time. The center button is a quick return to today.
                    RowLayout {
                        visible: root.selectedTab === "daily"
                        Layout.fillWidth: true
                        spacing: 6

                        RippleButton {
                            enabled: root.canGoPrevious
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.moveSelectedDay(-1)
                            Accessible.name: Translation.tr("Previous day")
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "chevron_left"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip { text: Translation.tr("Previous day") }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            enabled: !root.selectedIsToday
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.selectedDayKey = root.logic.curDayKey
                            Accessible.name: root.selectedIsToday
                                ? Translation.tr("Today") : Translation.tr("Back to today")
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                text: root.selectedDayLabel()
                            }
                            StyledToolTip {
                                text: Translation.tr("Back to today")
                            }
                        }

                        RippleButton {
                            enabled: root.canGoNext
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.moveSelectedDay(1)
                            Accessible.name: Translation.tr("Next day")
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip { text: Translation.tr("Next day") }
                        }
                    }

                    RowLayout {
                        visible: root.selectedTab === "weekly"
                        Layout.fillWidth: true
                        spacing: 6

                        RippleButton {
                            enabled: root.canGoPreviousWeek
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.moveSelectedWeek(-1)
                            Accessible.name: Translation.tr("Previous week")
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "chevron_left"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip { text: Translation.tr("Previous week") }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            enabled: !root.selectedWeekIsLatest
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.resetSelectedWeek()
                            Accessible.name: root.selectedWeekIsLatest
                                ? Translation.tr("Last complete week")
                                : Translation.tr("Back to last complete week")
                            contentItem: StyledText {
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                text: root.weekRangeLabel(root.selectedWeekStartKey)
                            }
                            StyledToolTip {
                                text: Translation.tr("Back to last complete week")
                            }
                        }

                        RippleButton {
                            enabled: root.canGoNextWeek
                            implicitWidth: 40
                            implicitHeight: 40
                            buttonRadius: Appearance.rounding.full
                            onClicked: root.moveSelectedWeek(1)
                            Accessible.name: Translation.tr("Next week")
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip { text: Translation.tr("Next week") }
                        }
                    }

                    ColumnLayout {
                        visible: root.selectedTab === "daily"
                        spacing: 0
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root.selectedIsToday
                                ? Translation.tr("Today") : root.selectedDayLabel()
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.hugeass + 6
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            text: fmt.dur(root.selectedDay.total)
                        }
                        StyledText {
                            visible: !root.selectedIsToday && !root.selectedDay.hasData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1Inactive
                            text: Translation.tr("No record for this day")
                        }
                        RowLayout {
                            visible: root.selectedIsToday && root.yesterdayTotal >= 0
                            spacing: 3
                            MaterialSymbol {
                                text: root.delta > 60 ? "trending_up" : root.delta < -60 ? "trending_down" : "trending_flat"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: (root.delta >= 0 ? "+" : "−") + fmt.dur(Math.abs(root.delta))
                                      + " " + Translation.tr("vs yesterday")
                            }
                        }
                    }

                    // AI agents working — the other dimension: how long agent
                    // sessions (claude/codex process trees) were actually
                    // burning CPU, focused or not, locked or not. Wall-clock
                    // union is the hero number ("my agents were working for
                    // 3h"); the sum and peak tell the parallelism story.
                    ColumnLayout {
                        visible: root.selectedTab === "daily" && root.aiAny
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "smart_toy"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurfaceVariant
                                text: Translation.tr("AI work time")
                            }
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            text: fmt.dur(root.selectedDay.aiU)
                        }
                        StyledText {
                            visible: root.aiCaption !== ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root.aiCaption
                        }
                        ColumnChart {
                            visible: root.selectedIsToday
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            values: root.t7.map(d => d.ai)
                            highlightIndex: 6
                            chartHeight: 56
                            xLabels: root.t7.map((d, i) => ({i, text: fmt.weekdayLetter(d.dow)}))
                            hoverLabel: (i, v) => `${root.mdLabel(root.t7[i].k)} · ${fmt.dur(v)}`
                            defaultLabel: Translation.tr("Daily average") + ` · ${fmt.dur(root.aiAvg7)}`
                        }
                    }

                    // Today by hour
                    ColumnLayout {
                        visible: root.selectedTab === "daily" && root.selectedIsToday
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            text: Translation.tr("Today by hour")
                        }
                        ColumnChart {
                            Layout.fillWidth: true
                            values: root.hourValues
                            highlightIndex: root.curHour
                            chartHeight: 72
                            maxBarWidth: 10
                            xLabels: [{i: 0, text: "0"}, {i: 6, text: "6"}, {i: 12, text: "12"},
                                      {i: 18, text: "18"}, {i: 23, text: "23"}]
                            hoverLabel: (i, v) => `${String(i).padStart(2, "0")}:00 · ${fmt.dur(v)}`
                            defaultLabel: {
                                const peak = root.hourValues.indexOf(Math.max(...root.hourValues))
                                return root.logic.todayTotal < 60 ? Translation.tr("No data yet")
                                    : Translation.tr("Peak") + ` ${String(peak).padStart(2, "0")}:00 · ${fmt.dur(root.hourValues[peak])}`
                            }
                        }
                    }

                    Loader {
                        visible: root.selectedTab === "weekly"
                        active: root.selectedTab === "weekly"
                        Layout.fillWidth: true
                        sourceComponent: WeeklyReport {
                            report: root.weekReport
                            heatmap: root.heatmap28
                            days30: root.t30
                            surfaceColor: background.color
                        }
                    }

                    ColumnLayout {
                        visible: root.selectedTab === "daily"
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            text: root.selectedIsToday
                                ? Translation.tr("Apps today") : Translation.tr("Apps on this day")
                        }
                        StyledText {
                            visible: root.ranking.length === 0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1Inactive
                            text: Translation.tr("No data yet")
                        }
                        Repeater {
                            model: root.ranking
                            delegate: ColumnLayout {
                                id: appRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colOnLayer1
                                        text: fmt.appName(appRow.modelData.n)
                                    }
                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        color: Appearance.colors.colOnSurfaceVariant
                                        text: fmt.dur(appRow.modelData.s)
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 5
                                    radius: 2.5
                                    color: Appearance.colors.colLayer2
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: root.topSeconds > 0 ? parent.width * (appRow.modelData.s / root.topSeconds) : 0
                                        radius: 2.5
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                        }
                    }

                }
            }
        }
    }
}
