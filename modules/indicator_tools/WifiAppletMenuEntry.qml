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
    property bool forceIconColumn: false
    property bool forceSpecialInteractionColumn: false

    readonly property bool hasIcon: menuEntry.icon.length > 0
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)

    colBackground: menuEntry.isSeparator
        ? Appearance.m3colors.m3outlineVariant
        : ColorUtils.transparentize(Appearance.colors.colLayer0)
    enabled: !menuEntry.isSeparator && menuEntry.enabled
    opacity: menuEntry.enabled || menuEntry.isSeparator ? 1 : 0.55
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
                active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox
                    && root.menuEntry.checkState !== Qt.Unchecked
                sourceComponent: MaterialSymbol {
                    text: root.menuEntry.checkState === Qt.PartiallyChecked
                        ? "check_indeterminate_small"
                        : "check"
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
                active: root.hasIcon
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.menuEntry.icon
                    implicitSize: 20
                    mipmap: true
                }
            }
        }

        StyledText {
            text: root.menuEntry.text
            font.pixelSize: Appearance.font.pixelSize.smallie
            Layout.fillWidth: true
        }

        Loader {
            active: root.menuEntry.hasChildren
            sourceComponent: MaterialSymbol {
                text: "chevron_right"
                iconSize: 20
            }
        }
    }
}
