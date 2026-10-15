import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.osu_indicator

/*
 * Bar slot entry: osu! play-state pill. A hit-circle glyph whose colour and
 * motion follow the daemon's state, plus an optional elapsed / countdown
 * text. Reads only the daemon's state file; see OsuState.qml.
 *
 *   off       hidden
 *   idle      dim ring, no dot
 *   menu      dim ring with a dim dot
 *   playing   accent ring + dot, approach circle shrinking onto it
 *   cooldown  accent ring, dot breathing, countdown text
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true
    visible: osu.shown

    MouseArea {
        id: root

        readonly property bool barVertical: barGroup.vertical
        readonly property int hPadding: root.barVertical ? 2 : 7

        implicitWidth: root.barVertical ? glyph.implicitWidth + root.hPadding * 2 : content.implicitWidth + root.hPadding * 2
        implicitHeight: root.barVertical ? glyph.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ConfigLoader {
            id: cfg
            owner: true
        }

        OsuState {
            id: osu
            showWhenIdle: cfg.options.showWhenIdle
            showWhenMenu: cfg.options.showWhenMenu
            showTimer: cfg.options.showTimer && !root.barVertical
            // Keep reading while hidden: the pill must come back on its own.
            active: true
        }

        // Palette: theme accent or osu! pink; secondary states soften toward
        // the inactive text tone so the state reads from the colour alone.
        readonly property color osuPink: "#ff66aa"
        readonly property color accent: cfg.options.accent === "osu" ? root.osuPink : Appearance.colors.colPrimary
        readonly property color dim: Appearance.colors.colOnLayer1Inactive
        readonly property color ringColor: osu.state === "playing" ? root.accent
                                         : osu.state === "cooldown" ? ColorUtils.mix(root.accent, root.dim, 0.65)
                                         : root.dim
        readonly property color dotColor: osu.state === "playing" ? root.accent
                                        : osu.state === "cooldown" ? ColorUtils.mix(root.accent, root.dim, 0.5)
                                        : root.dim
        readonly property bool dotShown: osu.state !== "idle"

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 6

            // Hit circle: ring + centre dot + looping approach circle.
            Item {
                id: glyph
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 20
                implicitHeight: 20
                width: implicitWidth
                height: implicitHeight

                Rectangle {
                    id: approach
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: root.accent
                    opacity: 0
                    visible: osu.state === "playing" && cfg.options.approachAnimation && barGroup.visible

                    SequentialAnimation on scale {
                        running: approach.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 2.2
                            to: 1.0
                            duration: 1100
                            easing.type: Easing.OutCubic
                        }
                        PauseAnimation {
                            duration: 300
                        }
                    }
                    SequentialAnimation on opacity {
                        running: approach.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 0.0
                            to: 0.7
                            duration: 250
                        }
                        NumberAnimation {
                            from: 0.7
                            to: 0.0
                            duration: 850
                            easing.type: Easing.InQuad
                        }
                        PauseAnimation {
                            duration: 300
                        }
                    }
                }

                Rectangle {
                    id: ring
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: width / 2
                    color: "transparent"
                    border.width: 2.5
                    border.color: root.ringColor
                    Behavior on border.color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: width / 2
                    color: root.dotColor
                    opacity: root.dotShown ? 1 : 0
                    scale: root.dotShown ? 1 : 0.4
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    // Cooldown: slow breathing while the grace period runs out.
                    SequentialAnimation on opacity {
                        running: osu.state === "cooldown" && barGroup.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 1.0
                            to: 0.35
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            from: 0.35
                            to: 1.0
                            duration: 900
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            StyledText {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.barVertical && osu.barText !== ""
                text: osu.barText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                // Tabular digits keep the width steady while seconds tick.
                font.features: ({ "tnum": 1 })
                color: osu.state === "playing" ? root.accent : Appearance.colors.colOnLayer1
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        OsuPopup {
            hoverTarget: root
            reader: osu
        }
    }
}
