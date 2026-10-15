import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import "OsuStateLogic.js" as Logic

/*
 * Hover popup: state, how long it has lasted, the cooldown countdown, and
 * the beatmap last selected or being played. StyledPopup is a tooltip; its
 * default property is one Item, so everything lives in the layout below.
 */
StyledPopup {
    id: root
    required property var reader

    function stateLabel() {
        switch (root.reader.state) {
        case "playing":
            return Translation.tr("Playing");
        case "cooldown":
            return Translation.tr("Between maps");
        case "menu":
            return Translation.tr("In the menus");
        case "idle":
            return Translation.tr("Open in the background");
        default:
            return Translation.tr("Not running");
        }
    }

    function stateIcon() {
        switch (root.reader.state) {
        case "playing":
            return "play_circle";
        case "cooldown":
            return "hourglass_top";
        case "menu":
            return "menu";
        default:
            return "pause_circle";
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
                text: root.stateIcon()
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
                animateChange: true
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `osu! · ${root.stateLabel()}`
                font {
                    weight: Font.DemiBold
                    pixelSize: Appearance.font.pixelSize.normal
                }
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "schedule"
                label: Translation.tr("For:")
                value: Logic.formatDuration(root.reader.elapsedSecs)
            }
            StyledPopupValueRow {
                visible: root.reader.state === "cooldown"
                Layout.fillWidth: true
                icon: "timer"
                label: Translation.tr("Back to menu in:")
                value: Logic.formatDuration(root.reader.cooldownLeftSecs)
            }
            StyledPopupValueRow {
                visible: root.reader.beatmap.title !== ""
                Layout.fillWidth: true
                icon: "music_note"
                label: root.reader.state === "playing" ? Translation.tr("Map:") : Translation.tr("Last map:")
                value: root.reader.beatmap.title
            }
            StyledPopupValueRow {
                visible: root.reader.beatmap.difficulty !== ""
                Layout.fillWidth: true
                icon: "speed"
                label: Translation.tr("Difficulty:")
                value: root.reader.beatmap.mapper !== "" ? `${root.reader.beatmap.difficulty} · ${root.reader.beatmap.mapper}` : root.reader.beatmap.difficulty
            }
        }

        StyledText {
            visible: root.reader.state === "playing" || root.reader.state === "cooldown"
            Layout.fillWidth: true
            Layout.maximumWidth: 260
            wrapMode: Text.WordWrap
            text: Translation.tr("Heavy builds wait while this shows.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
