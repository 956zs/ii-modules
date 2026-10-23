import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    name: Translation.tr("Keep awake")
    toggled: Idle.inhibit
    mainAction: () => {
        Idle.toggleInhibit()
    }
}
