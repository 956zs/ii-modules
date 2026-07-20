import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services

StyledPopup {
    id: root
    required property var logic

    function normalize(values) {
        const max = Math.max(...values, 1)
        return values.map(v => v / max)
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
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "download"
                label: Translation.tr("Received (boot):")
                value: root.logic.formatTotal(root.logic.totalRx)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "upload"
                label: Translation.tr("Sent (boot):")
                value: root.logic.formatTotal(root.logic.totalTx)
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
                Graph {
                    Layout.fillWidth: true
                    implicitWidth: 170
                    implicitHeight: 32
                    values: root.normalize(root.logic.downHistory)
                    color: Appearance.colors.colPrimary
                }
            }
            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "arrow_upward"
                    color: Appearance.colors.colTertiary
                    iconSize: Appearance.font.pixelSize.smaller
                }
                Graph {
                    Layout.fillWidth: true
                    implicitWidth: 170
                    implicitHeight: 32
                    values: root.normalize(root.logic.upHistory)
                    color: Appearance.colors.colTertiary
                }
            }
        }
    }
}
