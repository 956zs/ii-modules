import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.screentime

ColumnLayout {
    id: root
    required property var report
    required property var heatmap
    required property var days30
    required property color surfaceColor
    spacing: 14

    readonly property int comparisonToleranceSeconds: 60
    readonly property int maximumRankedApps: 5
    readonly property list<var> ranking: root.report.current.apps.slice(0, root.maximumRankedApps)
    readonly property var topApp: root.ranking.length > 0 ? root.ranking[0] : null
    readonly property real topSeconds: root.topApp ? root.topApp.s : 0

    function mdLabel(key) {
        const parts = key.split("-")
        return parts.length === 3 ? `${Number(parts[1])}/${Number(parts[2])}` : key
    }

    function weekdayLetter(index) {
        return [Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"),
                Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat"),
                Translation.tr("Sun")][index] ?? ""
    }

    function comparisonText(delta) {
        if (delta === null)
            return Translation.tr("Comparison unavailable")
        if (Math.abs(delta) <= root.comparisonToleranceSeconds)
            return Translation.tr("About the same as last week to date")
        const direction = delta > 0 ? "+" : "−"
        return direction + fmt.dur(Math.abs(delta)) + " "
            + Translation.tr("vs last week to date")
    }

    function heatmapLabel(dow, hour, minutes) {
        return `${root.weekdayLetter(dow)} ${String(hour).padStart(2, "0")}:00 · ${fmt.dur(minutes * 60)}`
    }

    Format { id: fmt }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Week %1 of %2")
                .arg(root.report.info.week).arg(root.report.info.year)
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.hugeass + 2
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
            text: fmt.dur(root.report.current.total)
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("%1 of %2 days recorded")
                .arg(root.report.current.coverage).arg(root.report.current.expectedDays)
        }
        RowLayout {
            spacing: 3
            MaterialSymbol {
                text: root.report.totalDelta === null ? "help"
                    : root.report.totalDelta > root.comparisonToleranceSeconds ? "trending_up"
                    : root.report.totalDelta < -root.comparisonToleranceSeconds
                        ? "trending_down" : "trending_flat"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.comparisonText(root.report.totalDelta)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurfaceVariant
            text: Translation.tr("This week")
        }
        ColumnChart {
            Layout.fillWidth: true
            values: root.report.current.days.map(day => day.total ?? 0)
            present: root.report.current.days.map(day => day.total !== null)
            referenceValue: root.report.current.coverage > 0
                ? root.report.current.total / root.report.current.coverage : -1
            chartHeight: 84
            xLabels: root.report.current.days.map((day, index) => ({
                i: index, text: root.weekdayLetter(index)
            }))
            hoverLabel: (index, value) => root.report.current.days[index].total === null
                ? `${root.mdLabel(root.report.current.days[index].k)} · ${Translation.tr("No record")}`
                : `${root.mdLabel(root.report.current.days[index].k)} · ${fmt.dur(value)}`
            defaultLabel: Translation.tr("Daily average") + " · "
                + fmt.dur(root.report.current.coverage > 0
                    ? root.report.current.total / root.report.current.coverage : 0)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurfaceVariant
            text: Translation.tr("Typical hours")
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("%1 of 28 days have hourly detail").arg(root.heatmap.coverage)
        }
        HourHeatmap {
            Layout.fillWidth: true
            values: root.heatmap.values
            dayLabels: [root.weekdayLetter(0), root.weekdayLetter(1),
                        root.weekdayLetter(2), root.weekdayLetter(3),
                        root.weekdayLetter(4), root.weekdayLetter(5),
                        root.weekdayLetter(6)]
            valueLabel: (dow, hour, minutes) => root.heatmapLabel(dow, hour, minutes)
            defaultLabel: root.heatmap.peak
                ? Translation.tr("Peak") + " · "
                    + root.heatmapLabel(root.heatmap.peak.dow, root.heatmap.peak.hour,
                                        root.heatmap.peak.minutes)
                : Translation.tr("Hourly detail starts accumulating after this update")
        }
    }

    ColumnLayout {
        visible: root.topApp !== null
        Layout.fillWidth: true
        spacing: 3

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurfaceVariant
            text: Translation.tr("Most used app")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: root.topApp ? fmt.appName(root.topApp.n) : ""
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: root.topApp ? fmt.dur(root.topApp.s) : ""
            }
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: root.topApp ? root.comparisonText(root.topApp.delta) : ""
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurfaceVariant
            text: Translation.tr("Apps this week")
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
                StyledText {
                    visible: root.report.comparisonAvailable
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.comparisonText(appRow.modelData.delta)
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
                        width: root.topSeconds > 0
                            ? parent.width * (appRow.modelData.s / root.topSeconds) : 0
                        radius: 2.5
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

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
            values: root.days30.map(day => day.total ?? 0)
            present: root.days30.map(day => day.total !== null)
            chartHeight: 72
            surfaceColor: root.surfaceColor
            xLabels: [{ i: 0, text: root.mdLabel(root.days30[0]?.k ?? "") },
                      { i: 15, text: root.mdLabel(root.days30[15]?.k ?? "") },
                      { i: 29, text: root.mdLabel(root.days30[29]?.k ?? "") }]
            hoverLabel: (index, value) => root.days30[index].total === null
                ? `${root.mdLabel(root.days30[index].k)} · ${Translation.tr("No record")}`
                : `${root.mdLabel(root.days30[index].k)} · ${fmt.dur(value)}`
            defaultLabel: {
                const maximum = Math.max(...root.days30.map(day => day.total ?? 0), 0)
                return Translation.tr("Max") + " · " + fmt.dur(maximum)
            }
        }
    }
}
