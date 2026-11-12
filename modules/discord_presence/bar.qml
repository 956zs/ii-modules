import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.discord_presence

/*
 * Bar slot entry: Discord Rich Presence pill for discord-rpc-proxy. A game
 * controller icon plus the detected game's name; left click toggles pause.
 * State comes from `discord-rpc-proxy watch`; see PresenceWatch.qml.
 *
 *   down      daemon not running: faint icon, no name
 *   idle      no game detected: dim icon
 *   playing   game detected: accent icon when shown on Discord + name
 *   paused    "hidden" icon, dimmed and struck-through name
 *
 * A small badge on the icon marks Discord not connected (error colour) or
 * the owner being away (tertiary colour).
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true
    visible: presence.shown

    MouseArea {
        id: root

        readonly property bool barVertical: barGroup.vertical
        readonly property int hPadding: root.barVertical ? 2 : 7
        readonly property real maxNameWidth: 160

        implicitWidth: root.barVertical ? glyph.implicitWidth + root.hPadding * 2 : content.implicitWidth + root.hPadding * 2
        implicitHeight: root.barVertical ? glyph.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: presence.toggle()

        ConfigLoader {
            id: cfg
            owner: true
        }

        PresenceWatch {
            id: presence
            binary: cfg.options.binary
            hideWhenIdle: cfg.options.hideWhenIdle
            popupOpen: root.containsMouse
        }

        readonly property color dim: Appearance.colors.colOnLayer1Inactive
        readonly property color iconColor: presence.kind === "playing" ? (presence.game.shown ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1) : root.dim
        readonly property color badgeColor: presence.marker === "disconnected" ? Appearance.colors.colError : Appearance.colors.colTertiary

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 5

            Item {
                id: glyph
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: icon.implicitWidth
                implicitHeight: icon.implicitHeight
                width: implicitWidth
                height: implicitHeight
                opacity: presence.kind === "down" ? 0.55 : 1
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    id: icon
                    anchors.centerIn: parent
                    text: presence.kind === "paused" ? "visibility_off" : "sports_esports"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.iconColor
                    animateChange: true
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                // Away / not-connected badge on the icon's corner.
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -1
                    anchors.bottomMargin: 1
                    width: 7
                    height: 7
                    radius: width / 2
                    color: root.badgeColor
                    opacity: presence.marker !== "" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            StyledText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.barVertical && presence.barText !== ""
                width: Math.min(implicitWidth, root.maxNameWidth)
                elide: Text.ElideRight
                text: presence.barText
                font.pixelSize: Appearance.font.pixelSize.small
                font.strikeout: presence.kind === "paused"
                color: presence.kind === "paused" ? root.dim : Appearance.colors.colOnLayer1
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        PresencePopup {
            hoverTarget: root
            reader: presence
        }
    }
}
