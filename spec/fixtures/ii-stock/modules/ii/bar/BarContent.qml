import qs.modules.ii.bar.weather
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property int centerSideModuleWidth: 360

    RippleButton {
        id: rightSidebarButton

        RowLayout {
            MaterialSymbol {
                text: Network.materialSymbol
            }
            MaterialSymbol {
                visible: BluetoothStatus.available
                text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
            }
        }
    }

    RowLayout {
            // Weather
            Loader {}
    }

    Row {
        Item {
            id: leftCenterGroup
        }

        Item {
            id: rightCenterGroup

            RowLayout {
                id: rightCenterGroupContent

                ClockWidget {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
