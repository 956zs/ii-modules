import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "DiscordLogic.js" as Logic

/*
 * Window-slot entry: a recent-Discord-notifications panel with All / DM / Server / Other tabs.
 * Data comes straight from the shell's Notifications service (live + persisted history), so
 * nothing here talks to Discord. Driven over IPC so a hotkey or a tablet button can use it:
 *   qs -c ii ipc --any-display call discordnotifs toggle | open | close | cycle | setFilter <name>
 */
Scope {
    id: root

    ConfigLoader {
        id: cfg
        owner: true
    }

    readonly property var defaultApps: ["discord", "vesktop", "equicord", "vencord", "legcord", "armcord"]
    readonly property string filter: Logic.isFilter(cfg.options.filter) ? cfg.options.filter : "all"
    property double nowMs: Date.now()
    readonly property var view: Logic.select(
        Notifications.list, Logic.parseList(cfg.options.appNames, root.defaultApps), root.filter, cfg.options.maxItems)

    function setFilter(name) {
        if (Logic.isFilter(name)) cfg.options.filter = name
    }

    function agoText(time) {
        const a = Logic.ago(root.nowMs, time)
        if (a.unit === "now") return Translation.tr("now")
        if (a.unit === "min") return Translation.tr("%1 min ago").arg(a.n)
        if (a.unit === "hour") return Translation.tr("%1 h ago").arg(a.n)
        return Translation.tr("%1 d ago").arg(a.n)
    }

    function filterLabel(name) {
        if (name === "dm") return Translation.tr("DMs")
        if (name === "server") return Translation.tr("Servers")
        if (name === "other") return Translation.tr("Other")
        return Translation.tr("All")
    }

    IpcHandler {
        target: "discordnotifs"

        function toggle(): void { panel.visible = !panel.visible }
        function open(): void { panel.visible = true }
        function close(): void { panel.visible = false }
        function cycle(): void {
            root.setFilter(Logic.nextFilter(root.filter))
            panel.visible = true
        }
        function setFilter(name: string): void {
            root.setFilter(name)
            panel.visible = true
        }
    }

    PanelWindow {
        id: panel
        visible: false
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:iimp-discordnotifs"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: panel.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top: true
        anchors.right: true
        margins {
            top: Appearance.sizes.barHeight
            right: 8
        }
        implicitWidth: cfg.options.panelWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: Math.min(
            background.implicitHeight + Appearance.sizes.elevationMargin * 2,
            (panel.screen?.height ?? 900) - Appearance.sizes.barHeight * 2)

        onVisibleChanged: if (visible) root.nowMs = Date.now()

        Timer {
            interval: 30000
            repeat: true
            running: panel.visible
            onTriggered: root.nowMs = Date.now()
        }

        HyprlandFocusGrab {
            active: panel.visible
            windows: [panel]
            onCleared: panel.visible = false
        }

        Item {
            anchors.fill: parent
            focus: panel.visible
            Keys.onEscapePressed: panel.visible = false

            StyledRectangularShadow {
                target: background
            }

            Rectangle {
                id: background
                anchors.fill: parent
                anchors.margins: Appearance.sizes.elevationMargin
                implicitHeight: content.implicitHeight + 24
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.windowRounding
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true

                ColumnLayout {
                    id: content
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "forum"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Discord notifications")
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: Logic.FILTERS
                            delegate: RippleButton {
                                required property string modelData
                                Layout.fillWidth: true
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                toggled: root.filter === modelData
                                buttonText: root.filterLabel(modelData) + "  " + (root.view.counts[modelData] ?? 0)
                                onClicked: root.setFilter(modelData)
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.bottomMargin: 12
                        visible: root.view.items.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("No recent notifications")
                    }

                    StyledListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 520)
                        visible: root.view.items.length > 0
                        clip: true
                        spacing: 6
                        model: ScriptModel {
                            values: root.view.items
                            objectProp: "id"
                        }
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: list.width
                            implicitHeight: rowLayout.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1

                            RowLayout {
                                id: rowLayout
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10

                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    radius: 18
                                    color: Appearance.colors.colLayer2
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        visible: row.modelData.image !== "" && status === Image.Ready
                                        source: row.modelData.image
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: row.modelData.kind === "dm" ? "person" : row.modelData.kind === "server" ? "tag" : "campaign"
                                        iconSize: Appearance.font.pixelSize.large
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer1
                                            text: row.modelData.sender
                                        }
                                        StyledText {
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            text: root.agoText(row.modelData.time)
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: row.modelData.kind === "server"
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colPrimary
                                        text: row.modelData.server !== ""
                                            ? row.modelData.channel + "  ·  " + row.modelData.server
                                            : row.modelData.channel
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        color: Appearance.colors.colOnLayer1
                                        text: row.modelData.body
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
