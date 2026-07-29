import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    ColumnLayout {
        StyledPopupValueRow {
            label: Translation.tr("System uptime:")
        }

        Column {
            Layout.fillWidth: true
        }
    }
}
