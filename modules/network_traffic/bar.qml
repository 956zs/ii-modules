import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.network_traffic

/*
 * Bar slot entry (Item root). Self-contained: own BarGroup pill, own logic
 * instance, own config file, hover popup.
 */
BarGroup {
    id: barGroup

    MouseArea {
        id: root
        implicitWidth: rowLayout.implicitWidth + 10 * 2
        implicitHeight: Appearance.sizes.barHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ConfigLoader { id: cfg }

        TrafficLogic {
            id: logic
            updateInterval: cfg.options.updateInterval
            excludeRegex: cfg.options.excludeRegex
        }

        RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: 2

            TextMetrics {
                id: speedTextMetrics
                text: "888.8M"
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
            }

            MaterialSymbol {
                fill: 0
                text: "arrow_downward"
                iconSize: Appearance.font.pixelSize.normal
                color: logic.downSpeed >= 1024 ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                implicitWidth: speedTextMetrics.width
                implicitHeight: downText.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: downText
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: logic.format(logic.downSpeed, false)
                }
            }

            MaterialSymbol {
                fill: 0
                text: "arrow_upward"
                iconSize: Appearance.font.pixelSize.normal
                color: logic.upSpeed >= 1024 ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
            }

            Item {
                implicitWidth: speedTextMetrics.width
                implicitHeight: upText.implicitHeight
                Layout.alignment: Qt.AlignVCenter

                StyledText {
                    id: upText
                    anchors.centerIn: parent
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: logic.format(logic.upSpeed, false)
                }
            }
        }

        TrafficPopup {
            hoverTarget: root
            logic: logic
        }
    }
}
