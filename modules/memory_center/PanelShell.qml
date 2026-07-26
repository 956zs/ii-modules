import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets

/*
 * Bar-adjacent floating frame for the detail panel (own copy of the
 * indicator_tools pattern — qs.mod cross-imports are forbidden): follows
 * the bar's position (top/bottom/left/right), closes on click-outside or
 * Esc. Starts visible because it is only created on the first toggle.
 */
PanelWindow {
    id: root
    default property alias content: slot.data
    property real panelWidth: 440
    // A click on the bar widget first collapses the panel through the focus
    // grab, then reaches the widget's toggle — the timestamp lets the
    // toggle tell "just closed by this same click" from a real reopen.
    property real lastCloseTime: 0

    visible: true
    onVisibleChanged: if (!visible) lastCloseTime = Date.now()
    function toggle() {
        root.visible = !root.visible
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:iimp-memory-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Sit next to the bar for every bar position.
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
