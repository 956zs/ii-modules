import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import qs.mod.network_traffic

/*
 * Hover popup. StyledPopup is a tooltip (it lives exactly as long as the
 * hover), so all interaction happens on the bar widget itself:
 *   left-click  — cycle the totals period  Boot → Today → This month
 *   right-click — expand/collapse the per-app ranking
 *
 * The bar entry owns that state and mirrors it in via statsPeriod /
 * appsExpanded.
 */
StyledPopup {
    id: root
    required property var logic
    required property var appTraffic
    property bool appsEnabled: true
    property string statsPeriod: "boot"
    property bool appsExpanded: false

    readonly property real periodRx: statsPeriod === "today" ? logic.todayRx
                                   : statsPeriod === "month" ? logic.monthRx
                                   : logic.totalRx
    readonly property real periodTx: statsPeriod === "today" ? logic.todayTx
                                   : statsPeriod === "month" ? logic.monthTx
                                   : logic.totalTx
    readonly property string periodLabel: statsPeriod === "today" ? Translation.tr("Today")
                                        : statsPeriod === "month" ? Translation.tr("This month")
                                        : Translation.tr("Boot")

    // Accumulated per-app totals for the selected period. acctRevision is
    // referenced so the binding re-evaluates as accounting rolls in.
    readonly property list<var> appRanking: {
        appTraffic.acctRevision
        return appTraffic.ranking(statsPeriod)
    }
    readonly property var topApp: appRanking.length > 0 ? appRanking[0] : null
    readonly property real topShare: {
        if (!topApp) return 0
        let total = 0
        for (const a of appRanking) total += a.rx + a.tx
        return total > 0 ? (topApp.rx + topApp.tx) / total : 0
    }

    function appName(name) {
        return name === appTraffic.otherKey ? Translation.tr("Other") : name
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        StyledPopupHeaderRow {
            icon: Network.materialSymbol
            label: Network.networkName
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "arrow_downward"
                label: Translation.tr("Download:")
                value: root.logic.format(root.logic.downSpeed, true)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "arrow_upward"
                label: Translation.tr("Upload:")
                value: root.logic.format(root.logic.upSpeed, true)
            }
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "history"
                label: Translation.tr("Statistics:")
                value: root.periodLabel
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "download"
                label: Translation.tr("Received:")
                value: root.logic.formatTotal(root.periodRx)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "upload"
                label: Translation.tr("Sent:")
                value: root.logic.formatTotal(root.periodTx)
            }
        }

        ColumnLayout {
            spacing: 4

            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "arrow_downward"
                    color: Appearance.colors.colPrimary
                    iconSize: Appearance.font.pixelSize.smaller
                }
                BezierGraph {
                    Layout.fillWidth: true
                    implicitWidth: 170
                    implicitHeight: 32
                    values: root.logic.downHistory
                    color: Appearance.colors.colPrimary
                    maxLabel: root.logic.format(Math.max(...root.logic.downHistory, 0), true)
                }
            }
            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "arrow_upward"
                    color: Appearance.colors.colTertiary
                    iconSize: Appearance.font.pixelSize.smaller
                }
                BezierGraph {
                    Layout.fillWidth: true
                    implicitWidth: 170
                    implicitHeight: 32
                    values: root.logic.upHistory
                    color: Appearance.colors.colTertiary
                    maxLabel: root.logic.format(Math.max(...root.logic.upHistory, 0), true)
                }
            }
        }

        // Per-app section: accumulated totals for the selected period. One
        // summary line; right-click on the bar widget expands the top five.
        ColumnLayout {
            visible: root.appsEnabled
            spacing: 4

            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "apps"
                    color: Appearance.colors.colOnSurfaceVariant
                    iconSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnSurfaceVariant
                    text: {
                        if (root.appTraffic.source === "none") return Translation.tr("Per-app stats unavailable")
                        if (!root.topApp) {
                            return root.appTraffic.source === "starting"
                                ? Translation.tr("Measuring per-app usage…")
                                : Translation.tr("No data yet")
                        }
                        return `${root.appName(root.topApp.name)}  ${Math.round(root.topShare * 100)}%`
                    }
                }
                StyledText {
                    visible: root.appTraffic.tcpOnly
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                    text: Translation.tr("TCP only")
                }
            }

            Repeater {
                model: root.appsExpanded ? root.appRanking.slice(0, 5) : []
                delegate: RowLayout {
                    required property var modelData
                    spacing: 4
                    Layout.leftMargin: Appearance.font.pixelSize.large + 4

                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 90
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.appName(modelData.name)
                    }
                    MaterialSymbol {
                        text: "arrow_downward"
                        color: Appearance.colors.colPrimary
                        iconSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.logic.formatTotal(modelData.rx)
                    }
                    MaterialSymbol {
                        text: "arrow_upward"
                        color: Appearance.colors.colTertiary
                        iconSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.logic.formatTotal(modelData.tx)
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Click: period · Right-click: apps")
        }
    }
}
