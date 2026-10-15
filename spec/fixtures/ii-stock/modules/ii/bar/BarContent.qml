import qs.modules.ii.bar.weather
import QtQuick
import QtQuick.Layouts
import qs.modules.common.functions

Item {
    id: root

    readonly property int centerSideModuleWidth: 360

    Row {
        id: middleSection

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

    MouseArea {
        id: barRightSideMouseArea

        RowLayout {
            id: rightSectionRowLayout

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

            SysTray {
                invertSide: Config?.options.bar.bottom
            }

            // Weather
            Loader {}
        }
    }
}
