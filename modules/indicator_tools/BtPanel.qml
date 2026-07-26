import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import qs.mod.indicator_tools

/*
 * Self-made Bluetooth panel on Quickshell's native Bluetooth service —
 * no CLI parsing at all; devices/pairing/connection are QML properties.
 */
PanelShell {
    id: root

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        RowLayout {
            spacing: 10

            MaterialSymbol {
                text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
                text: Translation.tr("Bluetooth")
            }
            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                toggled: Bluetooth.defaultAdapter?.discovering ?? false
                enabled: BluetoothStatus.enabled
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                }
                contentItem: MaterialSymbol {
                    id: scanIcon
                    horizontalAlignment: Text.AlignHCenter
                    text: "bluetooth_searching"
                    iconSize: Appearance.font.pixelSize.larger
                    color: (Bluetooth.defaultAdapter?.discovering ?? false) ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }
            StyledSwitch {
                checked: BluetoothStatus.enabled
                onClicked: {
                    if (Bluetooth.defaultAdapter)
                        Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                }
            }
        }

        StyledText {
            visible: !BluetoothStatus.available
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("No Bluetooth adapter")
        }

        ListView {
            id: list
            visible: BluetoothStatus.enabled
            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, 400)
            clip: true
            spacing: 2
            model: BluetoothStatus.friendlyDeviceList

            delegate: RippleButton {
                id: row
                required property var modelData
                width: list.width
                implicitHeight: rowContent.implicitHeight + 8 * 2
                buttonRadius: Appearance.rounding.small
                colBackground: row.modelData?.connected ? Appearance.colors.colSecondaryContainer : "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: {
                    const d = row.modelData
                    if (!d) return
                    if (d.connected) {
                        d.disconnect()
                    } else if (d.paired) {
                        d.connect()
                    } else {
                        d.pair()
                    }
                }

                contentItem: RowLayout {
                    id: rowContent
                    spacing: 10

                    MaterialSymbol {
                        text: Icons.getBluetoothDeviceMaterialSymbol(row.modelData?.icon || "")
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnSurfaceVariant
                            text: row.modelData?.name || Translation.tr("Unknown device")
                            textFormat: Text.PlainText
                        }
                        StyledText {
                            visible: (row.modelData?.connected || row.modelData?.paired) ?? false
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1Inactive
                            elide: Text.ElideRight
                            text: row.modelData?.connected ? Translation.tr("Connected") : Translation.tr("Paired")
                        }
                    }
                    RippleButton {
                        visible: (row.modelData?.paired ?? false) && !(row.modelData?.connected ?? false)
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        onClicked: row.modelData?.forget()
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: "delete"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                    }
                    MaterialSymbol {
                        visible: row.modelData?.connected ?? false
                        text: "check"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }
}
