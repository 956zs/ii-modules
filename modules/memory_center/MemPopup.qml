import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import qs.mod.memory_center

/*
 * Hover popup: headline percentage, the composition mini-bar, and the same
 * three-part legend the panel uses, plus a swap line. Pure tooltip — all
 * interaction lives on the bar widget and the detail panel.
 *
 * Legend rows double as the value display: a colour dot ties each row to
 * its segment (identity never rides on colour-matching text — the text
 * itself stays in text tokens).
 */
StyledPopup {
    id: root
    required property var mem

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 6

        component LegendRow: RowLayout {
            property color dotColor
            property string label
            property string value
            spacing: 6
            Layout.fillWidth: true

            Rectangle {
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: parent.dotColor
            }
            StyledText {
                text: parent.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: parent.value
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
        }

        RowLayout {
            spacing: 5

            MaterialSymbol {
                fill: 0
                font.weight: Font.DemiBold
                text: "memory"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: Translation.tr("Memory")
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: Math.round(root.mem.usedFrac * 100) + "%"
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
        }

        CompositionBar {
            Layout.fillWidth: true
            implicitWidth: 220
            implicitHeight: 10
            segments: [
                { value: root.mem.usedKb, color: Appearance.colors.colPrimary },
                { value: root.mem.reclaimKb, color: Appearance.colors.colSecondaryContainer },
                { value: root.mem.freeKb, color: Appearance.colors.colSurfaceContainerHighest }
            ]
        }

        LegendRow {
            dotColor: Appearance.colors.colPrimary
            label: Translation.tr("Apps")
            value: root.mem.fmt(root.mem.usedKb)
        }
        LegendRow {
            dotColor: Appearance.colors.colSecondaryContainer
            label: Translation.tr("Cache & buffers")
            value: root.mem.fmt(root.mem.reclaimKb)
        }
        LegendRow {
            dotColor: Appearance.colors.colSurfaceContainerHighest
            label: Translation.tr("Free")
            value: root.mem.fmt(root.mem.freeKb)
        }
        LegendRow {
            dotColor: Appearance.colors.colTertiary
            label: "Swap"
            value: root.mem.swapTotal > 0
                   ? `${root.mem.fmt(root.mem.swapUsedKb)} / ${root.mem.fmt(root.mem.swapTotal)}`
                   : Translation.tr("none")
        }

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Click for details & cleanup")
        }
    }
}
