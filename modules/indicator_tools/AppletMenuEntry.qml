pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

RippleButton {
    id: root
    required property QsMenuEntry menuEntry
    property string semanticStyleId: ""
    property bool forceIconColumn: false
    property bool forceSpecialInteractionColumn: false

    readonly property bool useSemanticStyle: root.semanticStyleId === "blueman" && !menuEntry.isSeparator
    readonly property bool nativeSelected: root.useSemanticStyle && menuEntry.icon.toLowerCase().includes("dialog-ok")
    readonly property bool hasNativeIcon: menuEntry.icon.length > 0 && !root.nativeSelected
    readonly property string fallbackIcon: root.useSemanticStyle ? root.bluemanIcon(menuEntry.text) : ""
    readonly property bool hasIcon: root.hasNativeIcon || root.fallbackIcon.length > 0
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None
    readonly property string labelText: root.useSemanticStyle ? root.displayLabel(menuEntry.text) : menuEntry.text

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)

    function normalLabel(text) {
        return text.replace(/_/g, "").replace(/\.\.\.$/, "…").trim()
    }

    function displayLabel(text) {
        const label = root.normalLabel(text)
        if (label.startsWith("Turn Bluetooth Off")) return Translation.tr("Turn Bluetooth off")
        if (label.startsWith("Turn Bluetooth On")) return Translation.tr("Turn Bluetooth on")
        if (label.startsWith("Make Discoverable")) return Translation.tr("Make discoverable")
        if (label.startsWith("Make Undiscoverable")) return Translation.tr("Stop discoverability")
        if (label.startsWith("Disconnect ")) return Translation.tr("Disconnect %1").arg(label.slice(11))
        if (label.startsWith("Send Files")) return Translation.tr("Send files")
        if (label.startsWith("Audio Profiles for ")) return Translation.tr("Audio profiles for %1").arg(label.slice(19))
        if (label.startsWith("Reconnect to")) return Translation.tr("Reconnect")
        if (/^Devices(?:…)?$/.test(label)) return Translation.tr("Devices")
        if (/^Adapters(?:…)?$/.test(label)) return Translation.tr("Adapters")
        if (/^Local Services(?:…)?$/.test(label)) return Translation.tr("Local services")
        if (label === "Plugins") return Translation.tr("Plugins")
        if (label === "Help") return Translation.tr("Help")
        if (label === "Exit") return Translation.tr("Exit")
        if (label === "Off") return Translation.tr("Off")
        return label
    }

    function bluemanIcon(text) {
        const label = root.normalLabel(text)
        if (label.startsWith("Turn Bluetooth Off")) return "bluetooth_disabled"
        if (label.startsWith("Turn Bluetooth On")) return "bluetooth"
        if (label.startsWith("Make Discoverable")) return "bluetooth_searching"
        if (label.startsWith("Disconnect ")) return "link_off"
        if (label.startsWith("Send Files")) return "send"
        if (label.startsWith("Audio Profiles for ")) return "headphones"
        if (label.startsWith("Audio and input profiles")) return "tune"
        if (label.startsWith("Reconnect to")) return "history"
        if (/^Devices(?:…)?$/.test(label)) return "devices"
        if (/^Adapters(?:…)?$/.test(label)) return "settings_input_antenna"
        if (/^Local Services(?:…)?$/.test(label)) return "settings"
        if (label === "Plugins") return "extension"
        if (label === "Help") return "help"
        if (label === "Exit") return "logout"
        if (label === "Off") return "bluetooth_disabled"
        if (label.includes("A2DP") && label.includes("SBC-XQ")) return "high_quality"
        if (label.includes("A2DP") && label.includes("AAC")) return "music_note"
        if (label.includes("A2DP")) return "headphones"
        if (label.includes("HSP/HFP")) return "headset_mic"
        return "bluetooth"
    }

    colBackground: menuEntry.isSeparator ? Appearance.m3colors.m3outlineVariant : ColorUtils.transparentize(Appearance.colors.colLayer0)
    enabled: !menuEntry.isSeparator
    opacity: menuEntry.enabled || menuEntry.isSeparator ? 1 : 0.65
    horizontalPadding: 12
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: menuEntry.isSeparator ? 1 : 36
    Layout.topMargin: menuEntry.isSeparator ? 4 : 0
    Layout.bottomMargin: menuEntry.isSeparator ? 4 : 0
    Layout.fillWidth: true

    Component.onCompleted: {
        if (menuEntry.isSeparator)
            root.buttonColor = root.colBackground
    }

    releaseAction: () => {
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry)
            return
        }
        menuEntry.triggered()
        root.dismiss()
    }
    altAction: event => event.accepted = false

    contentItem: RowLayout {
        id: contentItem
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 8
        visible: !root.menuEntry.isSeparator

        Item {
            visible: root.hasSpecialInteraction || root.forceSpecialInteractionColumn
            implicitWidth: 20
            implicitHeight: 20

            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.RadioButton
                sourceComponent: StyledRadioButton {
                    enabled: false
                    padding: 0
                    checked: root.menuEntry.checkState === Qt.Checked
                }
            }
            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox && root.menuEntry.checkState !== Qt.Unchecked
                sourceComponent: MaterialSymbol {
                    text: root.menuEntry.checkState === Qt.PartiallyChecked ? "check_indeterminate_small" : "check"
                    iconSize: 20
                }
            }
        }

        Item {
            visible: root.hasIcon || root.forceIconColumn
            implicitWidth: 20
            implicitHeight: 20

            Loader {
                anchors.centerIn: parent
                active: root.hasNativeIcon
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.menuEntry.icon
                    implicitSize: 20
                    mipmap: true
                }
            }
            Loader {
                anchors.centerIn: parent
                active: !root.hasNativeIcon && root.fallbackIcon.length > 0
                sourceComponent: MaterialSymbol {
                    text: root.fallbackIcon
                    iconSize: 20
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        StyledText {
            text: root.labelText
            font.pixelSize: Appearance.font.pixelSize.smallie
            Layout.fillWidth: true
        }

        Loader {
            active: root.menuEntry.hasChildren
            sourceComponent: MaterialSymbol { text: "chevron_right"; iconSize: 20 }
        }

        Loader {
            active: root.nativeSelected
            sourceComponent: MaterialSymbol {
                text: "check"
                iconSize: 20
                color: Appearance.colors.colPrimary
            }
        }
    }
}
