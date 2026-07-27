pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RippleButton {
    id: root

    required property QsMenuEntry menuEntry
    property string iconName: ""
    property string labelOverride: ""
    property string subtitle: ""
    property bool toggleStyle: false
    property bool actionStyle: false
    property bool showNativeIcon: true
    property bool dismissOnTrigger: true

    readonly property string label: labelOverride !== "" ? labelOverride : root.cleanLabel(menuEntry.text)
    readonly property bool hasNativeIcon: showNativeIcon && menuEntry.icon.length > 0
    readonly property bool checked: menuEntry.checkState === Qt.Checked
    readonly property bool partiallyChecked: menuEntry.checkState === Qt.PartiallyChecked

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle, title: string)

    function cleanLabel(text) {
        return String(text ?? "").replace(/_/g, "").replace(/\.\.\.$/, "…").trim()
    }

    function activate() {
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry, root.label)
            return
        }
        menuEntry.triggered()
        if (root.dismissOnTrigger)
            root.dismiss()
    }

    enabled: !menuEntry.isSeparator && menuEntry.enabled
    opacity: menuEntry.enabled ? 1 : 0.52
    Layout.fillWidth: true
    implicitHeight: menuEntry.isSeparator ? 1 : actionStyle ? 36 : subtitle !== "" ? 46 : 38
    horizontalPadding: actionStyle ? 12 : 6
    buttonRadius: Appearance.rounding.small
    colBackground: menuEntry.isSeparator
        ? Appearance.colors.colLayer0Border
        : actionStyle
            ? Appearance.colors.colSecondaryContainer
            : ColorUtils.transparentize(Appearance.colors.colLayer0)
    colBackgroundHover: actionStyle
        ? Appearance.colors.colSecondaryContainerHover
        : Appearance.colors.colLayer1Hover
    colRipple: actionStyle
        ? Appearance.colors.colSecondaryContainerActive
        : Appearance.colors.colLayer1Active

    Component.onCompleted: {
        if (menuEntry.isSeparator)
            root.buttonColor = root.colBackground
    }

    releaseAction: () => root.activate()
    altAction: event => event.accepted = false

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 10
        visible: !root.menuEntry.isSeparator

        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            visible: root.iconName !== "" || root.hasNativeIcon

            IconImage {
                anchors.centerIn: parent
                visible: root.hasNativeIcon
                asynchronous: true
                source: root.menuEntry.icon
                implicitSize: 21
                mipmap: true
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.hasNativeIcon && root.iconName !== ""
                text: root.iconName
                iconSize: 21
                color: root.actionStyle
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.label
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: root.actionStyle
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurface
            }

            StyledText {
                visible: root.subtitle !== ""
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.subtitle
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.actionStyle
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer1Inactive
            }
        }

        StyledSwitch {
            visible: root.toggleStyle
            enabled: false
            checked: root.checked || root.partiallyChecked
            opacity: 1
        }

        MaterialSymbol {
            visible: !root.toggleStyle && root.menuEntry.hasChildren
            text: "chevron_right"
            iconSize: 20
            color: root.actionStyle
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurfaceVariant
        }

        MaterialSymbol {
            visible: !root.toggleStyle
                && !root.menuEntry.hasChildren
                && root.menuEntry.buttonType !== QsMenuButtonType.None
                && (root.checked || root.partiallyChecked)
            text: root.partiallyChecked ? "check_indeterminate_small" : "check"
            iconSize: 20
            color: root.actionStyle
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colPrimary
        }
    }
}
