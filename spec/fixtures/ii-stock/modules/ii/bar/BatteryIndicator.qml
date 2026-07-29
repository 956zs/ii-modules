import qs.services
import QtQuick

MouseArea {
    id: root

    property bool borderless: Config.options.bar.borderless

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
