import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import qs.mod.androlink_status
import "StatusLogic.js" as Logic

/*
 * Bar slot entry: the phone androlink is linked to, as a capsule. Phone icon,
 * battery percent and a charging bolt; dimmed while the phone is
 * disconnected or androlink stopped updating its status file; a red dot on
 * the icon while the background helper is stopped; the unread count; a
 * camera mark while the phone is used as a webcam; "Saving battery" while
 * androlink waits for the phone to call back. Clicking opens a panel
 * with details and actions. Bar entries exist once per monitor and only
 * read; the low-battery reminder lives in the window slot (main.qml).
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true
    visible: root.model.shown

    MouseArea {
        id: root

        readonly property bool barVertical: barGroup.vertical
        readonly property int hPadding: root.barVertical ? 2 : 7
        readonly property var model: Logic.barModel(status.record, {
            showWhenNotRunning: cfg.options.showWhenNotRunning,
            showUnread: cfg.options.showUnread,
            threshold: cfg.options.lowBatteryThreshold
        })

        implicitWidth: content.implicitWidth + root.hPadding * 2
        implicitHeight: root.barVertical ? content.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        readonly property color dimColor: Appearance.colors.colOnLayer1Inactive
        readonly property color inkColor: root.model.dim ? root.dimColor : Appearance.colors.colOnLayer1
        readonly property color batteryColor: root.model.dim ? root.dimColor
            : root.model.low ? Appearance.colors.colError
            : root.model.charging ? Appearance.colors.colPrimary
            : Appearance.colors.colOnLayer1

        ConfigLoader {
            id: cfg
        }

        PhoneStatus {
            id: status
            heartbeatSecs: cfg.options.heartbeatSecs
            pollSecs: cfg.options.pollSecs
        }

        // Bumped on every reopen so the panel resets its phone pick and message.
        property int panelOpenCount: 0

        function togglePanel() {
            if (!panelLoader.active) {
                panelLoader.active = true; // PanelShell starts visible
                return;
            }
            const panel = panelLoader.item;
            if (!panel)
                return;
            if (panel.visible) {
                panel.visible = false;
            } else if (Date.now() - panel.lastCloseTime > 300) {
                // A click on the capsule first collapses the panel via its
                // focus grab, then lands here: don't instantly reopen.
                root.panelOpenCount++;
                panel.visible = true;
            }
        }

        onPressed: root.togglePanel()

        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: root.barVertical ? 1 : 7
            columnSpacing: 4
            rowSpacing: 1

            // Phone icon with the helper-stopped dot; it wiggles while ringing.
            Item {
                Layout.alignment: Qt.AlignCenter
                implicitWidth: phoneIcon.implicitWidth
                implicitHeight: phoneIcon.implicitHeight

                MaterialSymbol {
                    id: phoneIcon
                    anchors.centerIn: parent
                    text: root.model.quiet ? "mobile_off" : "smartphone"
                    fill: root.model.dim ? 0 : 1
                    iconSize: root.barVertical ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                    color: root.model.ringing ? Appearance.colors.colPrimary : root.inkColor
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    SequentialAnimation on rotation {
                        running: root.model.ringing && barGroup.visible
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) phoneIcon.rotation = 0
                        NumberAnimation { to: 14; duration: 70 }
                        NumberAnimation { to: -14; duration: 140 }
                        NumberAnimation { to: 10; duration: 120 }
                        NumberAnimation { to: 0; duration: 90 }
                        PauseAnimation { duration: 600 }
                    }
                }

                Rectangle {
                    visible: root.model.helperStopped && !root.model.quiet
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -1
                    anchors.topMargin: 1
                    width: 7
                    height: 7
                    radius: width / 2
                    color: Appearance.colors.colError
                    border.width: 1.5
                    border.color: Appearance.m3colors.m3background
                }
            }

            StyledText {
                visible: root.model.quiet && !root.barVertical
                Layout.alignment: Qt.AlignVCenter
                text: Translation.tr("Not running")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.dimColor
            }

            // The phone hung up to save battery; androlink waits for it.
            StyledText {
                visible: root.model.savingBattery && !root.barVertical
                Layout.alignment: Qt.AlignVCenter
                text: Translation.tr("Saving battery")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.dimColor
            }

            StyledText {
                visible: root.model.batteryText !== ""
                Layout.alignment: Qt.AlignCenter
                text: root.model.batteryText
                font.pixelSize: root.barVertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                // Tabular digits keep the capsule width steady.
                font.features: ({ "tnum": 1 })
                color: root.batteryColor
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            MaterialSymbol {
                visible: root.model.charging && !root.barVertical
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: -3
                text: "bolt"
                fill: 1
                iconSize: Appearance.font.pixelSize.normal
                color: root.model.dim ? root.dimColor : Appearance.colors.colPrimary
            }

            // Unread count pill.
            Rectangle {
                visible: root.model.unread > 0 && !root.model.quiet
                Layout.alignment: Qt.AlignCenter
                implicitHeight: 16
                implicitWidth: Math.max(implicitHeight, unreadText.implicitWidth + 8)
                radius: Appearance.rounding.full
                color: root.model.dim ? root.dimColor : Appearance.colors.colOnLayer1

                StyledText {
                    id: unreadText
                    anchors.centerIn: parent
                    text: root.model.unread > 99 ? "99+" : String(root.model.unread)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    // Opaque ink: the layer colours can be translucent.
                    color: Appearance.m3colors.m3background
                }
            }

            // Camera in use: a privacy mark, never dimmed.
            MaterialSymbol {
                visible: root.model.webcam
                Layout.alignment: Qt.AlignCenter
                text: "videocam"
                fill: 1
                iconSize: root.barVertical ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                color: Appearance.colors.colError
            }
        }

        LazyLoader {
            id: panelLoader
            active: false

            component: PanelShell {
                panelWidth: 340

                PhonePanel {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    reader: status
                    actionTimeoutSecs: cfg.options.actionTimeoutSecs
                    lowThreshold: cfg.options.lowBatteryThreshold
                    refreshMinIntervalSecs: cfg.options.refreshMinIntervalSecs
                    openCount: root.panelOpenCount
                }
            }
        }
    }
}
