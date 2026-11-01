import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services

/*
 * Hover tooltip for the bar icon: mode, feed state and board. StyledPopup's
 * default property is one Item, so everything lives in the layout below.
 */
StyledPopup {
    id: root

    property string modeText: ""
    property string stateText: ""
    property string boardText: ""

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        StyledText {
            text: Translation.tr("AULA key overlay")
            font {
                weight: Font.DemiBold
                pixelSize: Appearance.font.pixelSize.normal
            }
            color: Appearance.colors.colOnSurfaceVariant
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "visibility"
                label: Translation.tr("Mode:")
                value: root.modeText
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "sensors"
                label: Translation.tr("Feed:")
                value: root.stateText
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                visible: root.boardText !== ""
                icon: "keyboard"
                label: Translation.tr("Board:")
                value: root.boardText
            }
        }
    }
}
