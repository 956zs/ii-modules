import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.screentime

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

    visible: false
    function toggle() {
        root.visible = !root.visible
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
    readonly property list<var> ranking: {
        root.logic.revision
        return root.logic.ranking(9)
    }
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
    readonly property real avg7: root.t7.reduce((acc, d) => acc + d.total, 0) / 7

    // AI dimension: shown once there is anything to show — data today, a
    // matching session alive right now, or history from past days.
    readonly property bool aiAny: {
        root.logic.revision
        return root.logic.aiUnion >= 1 || root.logic.aiSessionsNow > 0
            || root.t7.some(d => d.ai >= 1)
    }
    readonly property real aiAvg7: root.t7.reduce((acc, d) => acc + d.ai, 0) / 7
    readonly property string aiCaption: {
        const bits = []
        if (root.logic.aiActiveNow > 0)
            bits.push(Translation.tr("%1 working now").arg(root.logic.aiActiveNow))
        if (root.logic.aiPeak > 1) {
            bits.push(Translation.tr("peak %1 parallel").arg(root.logic.aiPeak))
            bits.push(Translation.tr("sum %1").arg(fmt.dur(root.logic.aiSum)))
        }
        return bits.join(" · ")
    }

    function mdLabel(key) {
        const p = key.split("-")
        return p.length === 3 ? `${Number(p[1])}/${Number(p[2])}` : key
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
                        spacing: 6
                        MaterialSymbol {
                            text: "timelapse"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            text: Translation.tr("Screen time")
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Today")
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.hugeass + 6
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            text: fmt.dur(root.logic.todayTotal)
                        }
                        RowLayout {
                            visible: root.yesterdayTotal >= 0
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
                        visible: root.aiAny
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
                            text: fmt.dur(root.logic.aiUnion)
                        }
                        StyledText {
                            visible: root.aiCaption !== ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root.aiCaption
                        }
                        ColumnChart {
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

                    // Last 7 days
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            text: Translation.tr("Last 7 days")
                        }
                        ColumnChart {
                            Layout.fillWidth: true
                            values: root.t7.map(d => d.total)
                            highlightIndex: 6
                            chartHeight: 84
                            xLabels: root.t7.map((d, i) => ({i, text: fmt.weekdayLetter(d.dow)}))
                            hoverLabel: (i, v) => `${root.mdLabel(root.t7[i].k)} · ${fmt.dur(v)}`
                            defaultLabel: Translation.tr("Daily average") + ` · ${fmt.dur(root.avg7)}`
                        }
                    }

                    // Per-app ranking
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            text: Translation.tr("Apps today")
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

                    // Last 30 days
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                            text: Translation.tr("Last 30 days")
                        }
                        LineChart {
                            Layout.fillWidth: true
                            values: root.t30.map(d => d.total)
                            chartHeight: 72
                            surfaceColor: background.color
                            xLabels: [{i: 0, text: root.mdLabel(root.t30[0]?.k ?? "")},
                                      {i: 15, text: root.mdLabel(root.t30[15]?.k ?? "")},
                                      {i: 29, text: root.mdLabel(root.t30[29]?.k ?? "")}]
                            hoverLabel: (i, v) => `${root.mdLabel(root.t30[i].k)} · ${fmt.dur(v)}`
                            defaultLabel: {
                                const m = Math.max(...root.t30.map(d => d.total), 0)
                                return Translation.tr("Max") + ` · ${fmt.dur(m)}`
                            }
                        }
                    }
                }
            }
        }
    }
}
