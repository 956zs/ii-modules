import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.indicator_tools

/*
 * Multi-adapter networks panel: every wifi device gets its own section
 * (header + scan list), plus a bluetooth-tethered (PAN/NAP) section and an
 * ethernet section when applicable. Backed entirely by NetworksLogic's own
 * nmcli parsing — no stock Network service involved beyond the header icon.
 */
PanelShell {
    id: root

    NetworksLogic { id: logic }

    onVisibleChanged: {
        if (root.visible) logic.refresh()
    }

    function stateLabel(state) {
        if (state.startsWith("connecting")) return Translation.tr("Connecting…")
        if (state === "disconnected") return Translation.tr("Not connected")
        if (state === "unavailable") return Translation.tr("Unavailable")
        if (state === "unmanaged") return Translation.tr("Unmanaged")
        if (state.startsWith("connected")) return Translation.tr("Connected")
        return state
    }

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
                text: Translation.tr("Networks")
            }
            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: logic.rescan()
                contentItem: MaterialSymbol {
                    id: rescanIcon
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                    RotationAnimation on rotation {
                        running: logic.busy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                        onStopped: rescanIcon.rotation = 0
                    }
                }
            }
            StyledSwitch {
                checked: logic.wifiRadioEnabled
                onClicked: logic.toggleWifiRadio()
            }
        }

        StyledText {
            visible: logic.lastError !== ""
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: logic.lastError
        }

        StyledText {
            visible: !logic.wifiRadioEnabled
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Wi-Fi is off")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14

            Repeater {
                model: logic.sections
                delegate: Loader {
                    id: sectionLoader
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: modelData.kind === "wifi" ? wifiSectionComponent
                        : modelData.kind === "bluetooth" ? btSectionComponent
                        : ethSectionComponent
                    onLoaded: item.section = modelData
                }
            }
        }
    }

    Component {
        id: wifiSectionComponent
        ColumnLayout {
            id: wifiSection
            property var section: null
            property string expandedSsid: ""
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: !logic.wifiRadioEnabled ? "signal_wifi_off" : "wifi"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnSurfaceVariant
                        font.weight: Font.DemiBold
                        text: wifiSection.section.iface
                        textFormat: Text.PlainText
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1Inactive
                        text: wifiSection.section.state.startsWith("connected") && wifiSection.section.connection !== ""
                            ? wifiSection.section.connection
                            : root.stateLabel(wifiSection.section.state)
                        textFormat: Text.PlainText
                    }
                }
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    onClicked: logic.rescan(wifiSection.section.iface)
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "refresh"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
                RippleButton {
                    visible: wifiSection.section.state.startsWith("connected")
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    onClicked: logic.disconnectDevice(wifiSection.section.iface)
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "link_off"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            StyledText {
                visible: logic.wifiRadioEnabled && wifiSection.section.networks.length === 0
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1Inactive
                text: Translation.tr("No networks found")
            }

            StyledListView {
                visible: logic.wifiRadioEnabled && wifiSection.section.networks.length > 0
                Layout.fillWidth: true
                implicitHeight: Math.min(contentHeight, 260)
                clip: true
                spacing: 2
                model: wifiSection.section.networks

                delegate: ColumnLayout {
                    id: netRow
                    required property var modelData
                    width: ListView.view.width
                    spacing: 4

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: netRowContent.implicitHeight + 8 * 2
                        buttonRadius: Appearance.rounding.small
                        colBackground: netRow.modelData.inUse ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        onClicked: {
                            if (netRow.modelData.inUse) return
                            if (netRow.modelData.security === "") {
                                logic.connectWifi(wifiSection.section.iface, netRow.modelData.ssid)
                            } else {
                                wifiSection.expandedSsid = wifiSection.expandedSsid === netRow.modelData.ssid ? "" : netRow.modelData.ssid
                            }
                        }

                        contentItem: RowLayout {
                            id: netRowContent
                            spacing: 10

                            MaterialSymbol {
                                property int strength: netRow.modelData.signal
                                text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurfaceVariant
                                text: netRow.modelData.ssid
                                textFormat: Text.PlainText
                            }
                            MaterialSymbol {
                                visible: netRow.modelData.security !== "" || netRow.modelData.inUse
                                text: netRow.modelData.inUse ? "check" : wifiSection.expandedSsid === netRow.modelData.ssid ? "settings_ethernet" : "lock"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    RowLayout {
                        visible: wifiSection.expandedSsid === netRow.modelData.ssid
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialTextField {
                            id: passwordField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: Translation.tr("Password")
                            onAccepted: {
                                logic.connectWifi(wifiSection.section.iface, netRow.modelData.ssid, text)
                                wifiSection.expandedSsid = ""
                            }
                        }
                        RippleButton {
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: {
                                logic.connectWifi(wifiSection.section.iface, netRow.modelData.ssid, passwordField.text)
                                wifiSection.expandedSsid = ""
                            }
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
                            onClicked: wifiSection.expandedSsid = ""
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

    Component {
        id: btSectionComponent
        ColumnLayout {
            id: btSection
            property var section: null
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "bluetooth"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnSurfaceVariant
                    font.weight: Font.DemiBold
                    text: Translation.tr("Bluetooth network")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: btSection.section.connections
                    delegate: RippleButton {
                        id: connRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: connRowContent.implicitHeight + 8 * 2
                        buttonRadius: Appearance.rounding.small
                        colBackground: connRow.modelData.device !== "" ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: Appearance.colors.colLayer1Hover
                        colRipple: Appearance.colors.colLayer1Active
                        onClicked: {
                            if (connRow.modelData.device !== "")
                                logic.downConnection(connRow.modelData.name)
                            else
                                logic.upConnection(connRow.modelData.name)
                        }
                        contentItem: RowLayout {
                            id: connRowContent
                            spacing: 10
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnSurfaceVariant
                                text: connRow.modelData.name
                                textFormat: Text.PlainText
                            }
                            MaterialSymbol {
                                visible: connRow.modelData.device !== ""
                                text: "check"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }

                Repeater {
                    model: btSection.section.devices
                    delegate: RowLayout {
                        id: devRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1Inactive
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: devRow.modelData.mac
                            textFormat: Text.PlainText
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1Inactive
                            text: root.stateLabel(devRow.modelData.state)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: ethSectionComponent
        ColumnLayout {
            id: ethSection
            property var section: null
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "lan"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnSurfaceVariant
                        font.weight: Font.DemiBold
                        text: Translation.tr("Ethernet")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1Inactive
                        text: ethSection.section.state.startsWith("connected") && ethSection.section.connection !== ""
                            ? ethSection.section.connection
                            : root.stateLabel(ethSection.section.state)
                        textFormat: Text.PlainText
                    }
                }
                RippleButton {
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    onClicked: ethSection.section.state.startsWith("connected")
                        ? logic.disconnectDevice(ethSection.section.iface)
                        : logic.connectDevice(ethSection.section.iface)
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: ethSection.section.state.startsWith("connected") ? "link_off" : "power_settings_new"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }
}
