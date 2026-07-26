import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import qs.mod.screentime

/*
 * Hover popup for the bar widget. StyledPopup is a tooltip (lives exactly as
 * long as the hover), so it is read-only; the click that opens the detail
 * panel lands on the bar widget itself.
 *
 * Dataviz notes: single-series magnitude data, so one hue (Material primary)
 * carries all bars; identity comes from the app-name labels, values wear text
 * tokens, and each row's bar is proportional to the top app's time.
 */
StyledPopup {
    id: root
    property real todayTotal: 0
    property list<var> ranking: []
    property real yesterdayTotal: -1 // -1 = no record

    readonly property list<var> top5: root.ranking.slice(0, 5)
    readonly property real topSeconds: root.top5.length > 0 ? root.top5[0].s : 0
    readonly property real delta: root.todayTotal - root.yesterdayTotal

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        // StyledPopup's default property is a single Item — every helper,
        // visual or not, lives inside this layout.
        Format { id: fmt }

        Row {
            spacing: 5
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 0
                font.weight: Font.DemiBold
                text: "timelapse"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Screen time")
                font {
                    weight: Font.DemiBold
                    pixelSize: Appearance.font.pixelSize.normal
                }
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        // Stat tile: label, hero value, delta vs a named period.
        ColumnLayout {
            spacing: 0

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Today")
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: fmt.dur(root.todayTotal)
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

        StyledText {
            visible: root.top5.length === 0
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("No data yet")
        }

        // Top 5 apps, bar length proportional to the leader's time.
        ColumnLayout {
            visible: root.top5.length > 0
            spacing: 6

            Repeater {
                model: root.top5
                delegate: ColumnLayout {
                    id: appRow
                    required property var modelData
                    spacing: 2
                    Layout.preferredWidth: 190

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            text: fmt.appName(modelData.n)
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            text: fmt.dur(modelData.s)
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Appearance.colors.colLayer2
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: root.topSeconds > 0 ? parent.width * (appRow.modelData.s / root.topSeconds) : 0
                            radius: 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Click: details")
        }
    }
}
