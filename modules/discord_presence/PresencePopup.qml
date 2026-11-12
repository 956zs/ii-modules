import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import "PresenceLogic.js" as Logic

/*
 * Hover popup: what Discord is being shown, for how long the game has run,
 * its total play time, and the away / pause / connection state. StyledPopup
 * is a tooltip; its default property is one Item, so everything lives in the
 * layout below.
 */
StyledPopup {
    id: root
    required property var reader

    readonly property bool up: root.reader.kind !== "down"
    readonly property bool hasGame: root.up && root.reader.game !== null

    function stateLabel() {
        switch (root.reader.kind) {
        case "playing":
            return root.reader.game.shown ? Translation.tr("Showing a game") : Translation.tr("Game detected");
        case "paused":
            return Translation.tr("Paused");
        case "idle":
            return Translation.tr("No game detected");
        default:
            return Translation.tr("Daemon not running");
        }
    }

    function formatTotal(secs) {
        const parts = Logic.splitHours(secs);
        if (parts.hours > 0)
            return Translation.tr("%1 h %2 min").arg(parts.hours).arg(parts.paddedMinutes);
        return Translation.tr("%1 min").arg(parts.minutes);
    }

    function hint() {
        switch (root.reader.kind) {
        case "down":
            return Translation.tr("discord-rpc-proxy is not running. Click to try again now.");
        case "paused":
            return Translation.tr("Click to resume showing activity on Discord.");
        default:
            return Translation.tr("Click to pause: Discord shows no activity until you resume.");
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        Row {
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 0
                font.weight: Font.DemiBold
                text: root.reader.kind === "paused" ? "visibility_off" : "sports_esports"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
                animateChange: true
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `${Translation.tr("Discord presence")} · ${root.stateLabel()}`
                font {
                    weight: Font.DemiBold
                    pixelSize: Appearance.font.pixelSize.normal
                }
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            visible: root.up
            spacing: 4

            StyledPopupValueRow {
                visible: root.hasGame
                Layout.fillWidth: true
                icon: "sports_esports"
                label: Translation.tr("Game:")
                value: root.hasGame ? root.reader.game.name : ""
            }
            StyledPopupValueRow {
                visible: root.hasGame
                Layout.fillWidth: true
                icon: "visibility"
                label: Translation.tr("On Discord:")
                value: root.hasGame && root.reader.game.shown ? Translation.tr("Shown") : Translation.tr("Not shown")
            }
            StyledPopupValueRow {
                visible: root.hasGame && root.reader.game.startedAt > 0
                Layout.fillWidth: true
                icon: "schedule"
                label: Translation.tr("Running for:")
                value: Logic.formatClock(root.reader.elapsedSecs)
            }
            StyledPopupValueRow {
                visible: root.hasGame && root.reader.playtimeSecs >= 0
                Layout.fillWidth: true
                icon: "history"
                label: Translation.tr("Total play time:")
                value: root.formatTotal(root.reader.playtimeSecs)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "bedtime"
                label: Translation.tr("You:")
                value: root.reader.record.away ? Translation.tr("Away") : Translation.tr("Active")
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: root.reader.record.connected ? "check_circle" : "link_off"
                label: Translation.tr("Discord:")
                value: root.reader.record.connected ? Translation.tr("Connected") : Translation.tr("Not connected")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: 260
            wrapMode: Text.WordWrap
            text: root.hint()
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
