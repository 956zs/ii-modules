pragma ComponentBehavior: Bound

import QtQuick
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
    property string presentation: "row" // row, action, compact, quiet, toggle
    property string labelOverride: ""
    property string iconOverride: ""
    property bool stretch: presentation === "row" || presentation === "quiet"
        || presentation === "toggle"
    property bool dismissAfterTrigger: true

    readonly property bool useSemanticStyle: semanticStyleId === "blueman" && !menuEntry.isSeparator
    readonly property string normalizedLabel: normalLabel(menuEntry.text)
    readonly property string nativeIconName: String(menuEntry.icon ?? "")
    readonly property bool nativeSelected: useSemanticStyle
        && nativeIconName.toLowerCase().includes("dialog-ok")
    readonly property bool hasNativeIcon: nativeIconName.length > 0 && !nativeSelected
    readonly property string fallbackIcon: iconOverride !== "" ? iconOverride
        : useSemanticStyle ? bluemanIcon(menuEntry.text) : ""
    readonly property bool hasIcon: hasNativeIcon || fallbackIcon !== ""
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None
    readonly property string resolvedLabel: useSemanticStyle
        ? displayLabel(menuEntry.text) : String(menuEntry.text ?? "").trim()
    readonly property string labelText: labelOverride !== "" ? labelOverride
        : resolvedLabel !== "" ? resolvedLabel : Translation.tr("Bluetooth action")
    readonly property bool actionPresentation: presentation === "action" || presentation === "compact"
    readonly property bool togglePresentation: presentation === "toggle"
    readonly property bool toggleChecked: normalizedLabel.startsWith("Turn Bluetooth Off")
        || normalizedLabel.startsWith("Make Undiscoverable")

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle, title: string)

    function normalLabel(text) {
        return String(text ?? "").replace(/_/g, "").replace(/\.\.\.$/, "…").trim()
    }

    function displayLabel(text) {
        const label = normalLabel(text)
        if (label.startsWith("Turn Bluetooth Off")) return Translation.tr("Turn Bluetooth off")
        if (label.startsWith("Turn Bluetooth On")) return Translation.tr("Turn Bluetooth on")
        if (label.startsWith("Make Discoverable")) return Translation.tr("Make discoverable")
        if (label.startsWith("Make Undiscoverable")) return Translation.tr("Stop discoverability")
        if (label.startsWith("Disconnect ")) return Translation.tr("Disconnect %1").arg(label.slice(11))
        if (label.startsWith("Send Files")) return Translation.tr("Send files")
        if (label.startsWith("Audio Profiles for "))
            return Translation.tr("Audio profiles for %1").arg(label.slice(19))
        if (label.startsWith("Reconnect to")) return Translation.tr("Reconnect")
        if (label.startsWith("Audio and input profiles on "))
            return Translation.tr("Audio and input profiles")
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
        const label = normalLabel(text)
        if (label.startsWith("Turn Bluetooth Off")) return "bluetooth_disabled"
        if (label.startsWith("Turn Bluetooth On")) return "bluetooth"
        if (label.startsWith("Make Discoverable")) return "bluetooth_searching"
        if (label.startsWith("Make Undiscoverable")) return "visibility_off"
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

    colBackground: menuEntry.isSeparator
        ? Appearance.m3colors.m3outlineVariant
        : actionPresentation ? Appearance.colors.colSecondaryContainer
        : ColorUtils.transparentize(Appearance.colors.colLayer0)
    colBackgroundHover: actionPresentation ? Appearance.colors.colSecondaryContainerHover
        : Appearance.colors.colSurfaceContainerHighest
    colRipple: actionPresentation ? Appearance.colors.colSecondaryContainerActive
        : Appearance.colors.colLayer2
    enabled: !menuEntry.isSeparator && menuEntry.enabled
    opacity: menuEntry.enabled || menuEntry.isSeparator ? 1 : 0.5
    horizontalPadding: presentation === "compact" ? 8 : 10
    buttonRadius: Appearance.rounding.small
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: menuEntry.isSeparator ? 1 : presentation === "compact" ? 32 : 36
    Layout.fillWidth: stretch

    Component.onCompleted: if (menuEntry.isSeparator) root.buttonColor = root.colBackground

    releaseAction: () => {
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry, root.labelText)
            return
        }
        menuEntry.triggered()
        if (root.dismissAfterTrigger)
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
        spacing: 6
        visible: !root.menuEntry.isSeparator

        Item {
            visible: root.hasSpecialInteraction
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
                active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox
                    && root.menuEntry.checkState !== Qt.Unchecked
                sourceComponent: MaterialSymbol {
                    text: root.menuEntry.checkState === Qt.PartiallyChecked
                        ? "check_indeterminate_small" : "check"
                    iconSize: 20
                    color: root.actionPresentation ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnSurface
                }
            }
        }

        Item {
            visible: root.hasIcon
            implicitWidth: 20
            implicitHeight: 20

            Loader {
                anchors.centerIn: parent
                active: root.hasNativeIcon
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.nativeIconName
                    implicitSize: 20
                    mipmap: true
                }
            }
            Loader {
                anchors.centerIn: parent
                active: !root.hasNativeIcon && root.fallbackIcon !== ""
                sourceComponent: MaterialSymbol {
                    text: root.fallbackIcon
                    iconSize: 20
                    color: root.actionPresentation ? Appearance.colors.colOnSecondaryContainer
                        : Appearance.colors.colOnSurfaceVariant
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.labelText
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: root.actionPresentation ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurface
        }

        MaterialSymbol {
            visible: root.menuEntry.hasChildren
            text: "chevron_right"
            iconSize: 20
            color: root.actionPresentation ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurfaceVariant
        }

        MaterialSymbol {
            visible: root.nativeSelected
            text: "check"
            iconSize: 20
            color: Appearance.colors.colPrimary
        }

        StyledSwitch {
            visible: root.togglePresentation
            enabled: false
            checked: root.toggleChecked
        }
    }
}
