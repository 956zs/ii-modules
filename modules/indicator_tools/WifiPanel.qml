import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.indicator_tools

/*
 * Self-made WiFi panel bound to the stock Network service — the nmcli
 * plumbing (scan, profiles, password flow) is stock's; the UI is ours.
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
                text: Network.materialSymbol
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
                text: Translation.tr("Wi-Fi")
            }
            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: Network.rescanWifi()
                contentItem: MaterialSymbol {
                    id: rescanIcon
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    RotationAnimation on rotation {
                        running: Network.wifiScanning
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                        onStopped: rescanIcon.rotation = 0
                    }
                }
            }
            StyledSwitch {
                checked: Network.wifiEnabled
                onClicked: Network.toggleWifi()
            }
        }

        StyledText {
            visible: !Network.wifiEnabled
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Wi-Fi is off")
        }

        StyledListView {
            id: list
            visible: Network.wifiEnabled
            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, 400)
            clip: true
            spacing: 2
            model: Network.friendlyWifiNetworks

            delegate: RippleButton {
                id: row
                required property var modelData
                width: list.width
                implicitHeight: rowContent.implicitHeight + 8 * 2
                buttonRadius: Appearance.rounding.small
                colBackground: row.modelData?.active ? Appearance.colors.colSecondaryContainer : "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: {
                    if (!row.modelData.active)
                        Network.connectToWifiNetwork(row.modelData)
                }

                contentItem: ColumnLayout {
                    id: rowContent
                    spacing: 6

                    RowLayout {
                        spacing: 10

                        MaterialSymbol {
                            property int strength: row.modelData?.strength ?? 0
                            text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnSurfaceVariant
                            text: row.modelData?.ssid ?? Translation.tr("Unknown")
                            textFormat: Text.PlainText
                        }
                        MaterialSymbol {
                            visible: (row.modelData?.isSecure || row.modelData?.active) ?? false
                            text: row.modelData?.active ? "check" : Network.wifiConnectTarget === row.modelData ? "settings_ethernet" : "lock"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    // Inline password prompt (stock askingPassword flow).
                    RowLayout {
                        visible: row.modelData?.askingPassword ?? false
                        spacing: 8

                        MaterialTextField {
                            id: passwordField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: Translation.tr("Password")
                            onAccepted: Network.changePassword(row.modelData, text)
                        }
                        RippleButton {
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: Network.changePassword(row.modelData, passwordField.text)
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "arrow_forward"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        RippleButton {
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: row.modelData.askingPassword = false
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "close"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
