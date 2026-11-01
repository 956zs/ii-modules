import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import qs.mod.aula_keys
import "AulaKeysLogic.js" as Logic
import "AulaHub.js" as Hub

/*
 * Bar slot entry: keyboard icon whose colour shows the overlay at a glance
 * (dim: hidden or off, accent: feed live, warning tint: board waiting, busy
 * or the feed failing), an optional KPS figure, a hover tooltip, and a
 * click-to-open quick settings panel. Bar entries exist once per monitor;
 * the feed lives only in the window slot (main.qml), read through
 * AulaHub.js. Settings changes go to the shared module config file.
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true

    MouseArea {
        id: root

        readonly property bool barVertical: barGroup.vertical
        readonly property int hPadding: root.barVertical ? 2 : 7

        implicitWidth: content.implicitWidth + root.hPadding * 2
        implicitHeight: root.barVertical ? content.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ConfigLoader {
            id: barCfg
        }

        // main.qml once it has registered; re-read every second so a module
        // reload (new owner object) is picked up.
        property var owner: Hub.current()
        Timer {
            interval: 1000
            repeat: true
            running: true
            onTriggered: {
                const current = Hub.current();
                if (current !== root.owner)
                    root.owner = current;
            }
        }

        readonly property var feed: root.owner ? root.owner.feed : null
        readonly property string feedStatus: root.feed ? root.feed.status : ""
        readonly property string barState: root.owner ? Logic.barState(barCfg.options.mode, root.owner.shown, root.feedStatus) : "off"
        readonly property bool showKps: barCfg.options.barShowKps && root.barState === "live" && !root.barVertical

        readonly property color dim: Appearance.colors.colOnLayer1Inactive
        readonly property color iconColor: {
            switch (root.barState) {
            case "live":
                return Appearance.colors.colPrimary;
            case "starting":
                return ColorUtils.mix(Appearance.colors.colPrimary, root.dim, 0.5);
            case "warn":
                return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colOnLayer1, 0.55);
            default:
                return root.dim;
            }
        }

        function modeText() {
            switch (Logic.normalizeMode(barCfg.options.mode)) {
            case "focused":
                return Translation.tr("While osu! is focused");
            case "always":
                return Translation.tr("Always");
            case "off":
                return Translation.tr("Off");
            default:
                return Translation.tr("While playing osu!");
            }
        }

        function stateText() {
            if (!root.owner)
                return Translation.tr("Overlay not loaded");
            switch (root.barState) {
            case "off":
                return Translation.tr("Overlay off");
            case "hidden":
                return Translation.tr("Hidden, waiting for osu!");
            case "starting":
                return Translation.tr("Connecting…");
            case "live":
                return Translation.tr("Live");
            }
            switch (root.feedStatus) {
            case "waiting":
                return Translation.tr("Waiting for the keyboard");
            case "busy":
                return Translation.tr("Keyboard busy (aulactl or aula-gui is using it)");
            case "lost":
                return Translation.tr("Keyboard disconnected");
            case "error":
                return Translation.tr("Feed error: %1").arg(root.feed ? root.feed.errorText : "");
            default:
                return Translation.tr("Feed stopped, retrying");
            }
        }

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
                // A click on the icon first collapses the panel via its
                // focus grab, then lands here: don't instantly reopen.
                panel.visible = true;
            }
        }

        onPressed: root.togglePanel()

        // Testability hook: `qs -c ii ipc --any-display call aula_keys_bar toggle`.
        IpcHandler {
            target: "aula_keys_bar"

            function toggle(): void {
                root.togglePanel();
            }
        }

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: 3

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                fill: root.barState === "live" ? 1 : 0
                text: "keyboard"
                iconSize: root.barVertical ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                color: root.iconColor
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            StyledText {
                visible: root.showKps
                Layout.alignment: Qt.AlignVCenter
                text: root.feed ? String(root.feed.kpsNow) : ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                // Tabular digits keep the width steady while KPS changes.
                font.features: ({ "tnum": 1 })
                color: root.iconColor
            }
        }

        BarPopup {
            hoverTarget: root
            modeText: root.modeText()
            stateText: root.stateText()
            boardText: root.feed ? root.feed.product.replace(/[<>&]/g, "") : ""
        }

        LazyLoader {
            id: panelLoader
            active: false

            component: PanelShell {
                panelWidth: 380

                QuickPanel {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    config: barCfg
                    owner: root.owner
                    barState: root.barState
                    stateText: root.stateText()
                }
            }
        }
    }
}
