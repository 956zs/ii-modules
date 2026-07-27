pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.indicator_tools

PopupWindow {
    id: root
    required property QsMenuHandle menuHandle
    property string semanticStyleId: ""
    property real popupBackgroundMargin: 0

    signal menuClosed()
    signal menuOpened(qsWindow: var)

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin

    implicitHeight: {
        let result = 0
        for (const child of stackView.children)
            result = Math.max(child.implicitHeight, result)
        return result + popupBackground.padding * 2 + root.padding * 2
    }
    implicitWidth: {
        let result = 0
        for (const child of stackView.children)
            result = Math.max(child.implicitWidth, result)
        return Math.max(320, result + popupBackground.padding * 2 + root.padding * 2)
    }

    function open() {
        root.visible = true
        root.menuOpened(root)
    }
    function close() {
        root.visible = false
        while (stackView.depth > 1)
            stackView.pop()
        root.menuClosed()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop()
        }

        StyledRectangularShadow { target: popupBackground; opacity: popupBackground.opacity }

        Rectangle {
            id: popupBackground
            readonly property real padding: 4
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.padding
            }
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            opacity: 0
            Component.onCompleted: opacity = 1
            implicitWidth: Math.max(300, stackView.implicitWidth + padding * 2)
            implicitHeight: stackView.implicitHeight + padding * 2

            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Behavior on implicitHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }
            Behavior on implicitWidth { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }

            StackView {
                id: stackView
                anchors { fill: parent; margins: popupBackground.padding }
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}
                implicitWidth: currentItem.implicitWidth
                implicitHeight: currentItem.implicitHeight
                initialItem: SubMenu { handle: root.menuHandle }
            }
        }
    }

    component NoAnim: Transition { NumberAnimation { duration: 0 } }

    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false
        opacity: shown ? 1 : 0
        spacing: 0

        Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener { id: menuOpener; menu: submenu.handle }

        Loader {
            Layout.fillWidth: true
            visible: !submenu.isSubMenu
            active: visible
            sourceComponent: RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                spacing: 8

                MaterialSymbol {
                    text: "bluetooth"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        text: Translation.tr("Bluetooth")
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        text: Translation.tr("Blueman controls")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                }
            }
        }

        Rectangle {
            visible: !submenu.isSubMenu
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            implicitHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: RippleButton {
                id: backButton
                buttonRadius: popupBackground.radius - popupBackground.padding
                horizontalPadding: 12
                implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
                implicitHeight: 36
                downAction: () => stackView.pop()
                contentItem: RowLayout {
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                        leftMargin: backButton.horizontalPadding
                        rightMargin: backButton.horizontalPadding
                    }
                    spacing: 8
                    MaterialSymbol { iconSize: 20; text: "chevron_left" }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Back") }
                }
            }
        }

        Repeater {
            id: menuEntriesRepeater
            property bool iconColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    const entry = menuOpener.children.values[i]
                    if (entry.icon.length > 0 || (root.semanticStyleId === "blueman" && !entry.isSeparator))
                        return true
                }
                return false
            }
            property bool specialInteractionColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].buttonType !== QsMenuButtonType.None)
                        return true
                }
                return false
            }
            model: menuOpener.children
            delegate: AppletMenuEntry {
                required property QsMenuEntry modelData
                semanticStyleId: root.semanticStyleId
                forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                menuEntry: modelData
                buttonRadius: popupBackground.radius - popupBackground.padding
                onDismiss: root.close()
                onOpenSubmenu: handle => stackView.push(subMenuComponent.createObject(null, {
                    handle,
                    isSubMenu: true
                }))
            }
        }
    }

    Component { id: subMenuComponent; SubMenu {} }
}
