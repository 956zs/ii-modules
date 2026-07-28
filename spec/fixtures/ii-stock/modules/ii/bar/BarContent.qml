import QtQuick
import QtQuick.Layouts

Item {
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
}
