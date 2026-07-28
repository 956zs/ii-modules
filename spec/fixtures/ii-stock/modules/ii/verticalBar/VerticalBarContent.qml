import QtQuick
import QtQuick.Layouts

Item {
    ColumnLayout {
            spacing: 10
            Bar.LeftSidebarButton {
            }
    }
    ColumnLayout {
        RippleButton {
            id: rightSidebarButton

            ColumnLayout {
                MaterialSymbol {
                    text: Network.materialSymbol
                }
                MaterialSymbol {
                    visible: BluetoothStatus.available
                    text: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"
                }
            }
        }

        Bar.SysTray {
            vertical: true
        }
    }
}
