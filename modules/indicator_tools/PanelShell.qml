import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

/*
 * Shared frame for the WiFi/Bluetooth panels: a bar-adjacent floating window
 * that follows the bar's position (top/bottom/left/right), takes keyboard
 * focus on demand (password fields), and closes on click-outside or Esc.
 */
PanelWindow {
    id: root
    default property alias content: slot.data
    property real panelWidth: 360

    visible: false
    function toggle() {
        root.visible = !root.visible
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:iimp-indicator-tools"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Sit next to the indicators cluster for every bar position.
    anchors.top: !Config.options.bar.vertical && !Config.options.bar.bottom
    anchors.bottom: Config.options.bar.bottom || Config.options.bar.vertical
    anchors.left: Config.options.bar.vertical && !Config.options.bar.bottom
    anchors.right: !Config.options.bar.vertical || Config.options.bar.bottom
    margins {
        top: Appearance.sizes.barHeight
        bottom: Config.options.bar.vertical ? 8 : Appearance.sizes.barHeight
        left: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 8
        right: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 8
    }

    implicitWidth: root.panelWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: background.implicitHeight + Appearance.sizes.elevationMargin * 2

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.visible = false
    }

    Item {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.visible = false

        StyledRectangularShadow {
            target: background
        }

        Rectangle {
            id: background
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            implicitHeight: slotColumn.implicitHeight + 16 * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Item {
                id: slotColumn
                anchors {
                    fill: parent
                    margins: 16
                }
                implicitHeight: childrenRect.height

                Item {
                    id: slot
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: childrenRect.height
                    height: childrenRect.height
                }
            }
        }
    }
}
