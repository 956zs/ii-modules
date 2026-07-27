pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RippleButton {
    id: root

    required property QsMenuEntry menuEntry
    property string semanticRole: "other"

    readonly property string displayLabel: root.normalizedLabel(root.menuEntry.text)
    readonly property bool hasToggle: root.menuEntry.buttonType !== QsMenuButtonType.None
    readonly property bool entryChecked: root.menuEntry.checkState !== Qt.Unchecked
    readonly property string materialIcon: root.semanticIcon(
        root.displayLabel,
        root.menuEntry.hasChildren,
        root.menuEntry.buttonType,
        root.semanticRole)

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)

    function normalizedLabel(text) {
        const source = String(text ?? "")
        let result = ""
        for (let i = 0; i < source.length; ++i) {
            if (source[i] !== "_") {
                result += source[i]
                continue
            }
            if (i + 1 < source.length && source[i + 1] === "_") {
                result += "_"
                ++i
            } else if (i + 1 >= source.length) {
                result += "_"
            }
        }
        return result.replace(/\.\.\.$/, "…").trim()
    }

    // Pure semantic fallback: only D-Bus metadata and the normalized label
    // select an icon; GTK icon names never enter the rendered UI.
    function semanticIcon(text, hasChildren, buttonType, role) {
        const label = String(text ?? "").toLowerCase()
        const isToggle = buttonType !== QsMenuButtonType.None

        if (label.includes("ethernet")) return "lan"
        if (label.includes("wi-fi") || label.includes("wifi") || label.includes("wireless"))
            return label.includes("hidden") ? "wifi_lock" : "wifi"
        if (/(^|\s)vpn(\s|$)/.test(label)) return "vpn_key"
        if (label.includes("mobile broadband")) return "signal_cellular_alt"
        if (label.startsWith("disconnect")) return "link_off"
        if (label.includes("connection information")) return "info"
        if (label.startsWith("edit ") || label.startsWith("configure ")) return "settings"
        if (label.startsWith("create ") || label.startsWith("new ")) return "add"
        if (label.includes("available network")) return "wifi_find"
        if (isToggle) return "toggle_on"
        if (role === "wifi") return "wifi"
        if (role === "vpn") return "vpn_key"
        if (role === "controls") return "settings_ethernet"
        if (role === "manage") return "settings"
        if (role === "connections") return "network_check"
        if (hasChildren) return "account_tree"
        return label.length > 0 ? "network_node" : "more_horiz"
    }

    enabled: !root.menuEntry.isSeparator
    opacity: 1
    horizontalPadding: 10
    implicitWidth: contentRow.implicitWidth + horizontalPadding * 2
    implicitHeight: root.menuEntry.isSeparator ? 1 : root.hasToggle ? 42 : 38
    Layout.fillWidth: true
    Layout.leftMargin: root.menuEntry.isSeparator ? 8 : 4
    Layout.rightMargin: root.menuEntry.isSeparator ? 8 : 4
    Layout.topMargin: root.menuEntry.isSeparator ? 4 : 0
    Layout.bottomMargin: root.menuEntry.isSeparator ? 4 : 0

    buttonRadius: Appearance.rounding.small
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    buttonColor: root.menuEntry.isSeparator
        ? Appearance.colors.colLayer0Border
        : (root.hovered ? root.colBackgroundHover : root.colBackground)

    releaseAction: () => {
        if (root.menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry)
            return
        }
        root.menuEntry.triggered()
        root.dismiss()
    }
    altAction: event => event.accepted = false

    contentItem: RowLayout {
        id: contentRow

        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10
        visible: !root.menuEntry.isSeparator

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 20
            text: root.materialIcon
            iconSize: 20
            color: root.entryChecked && root.hasToggle
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.displayLabel.length > 0
                ? root.displayLabel
                : Translation.tr("Unnamed item")
            textFormat: Text.PlainText
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSurface
        }

        Loader {
            active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox
            sourceComponent: StyledSwitch {
                checked: root.entryChecked
                enabled: false
                scale: 0.65
            }
        }

        Loader {
            active: root.menuEntry.buttonType === QsMenuButtonType.RadioButton
            sourceComponent: StyledRadioButton {
                checked: root.entryChecked
                enabled: false
                padding: 0
            }
        }

        MaterialSymbol {
            visible: root.menuEntry.hasChildren
            text: "chevron_right"
            iconSize: 20
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
