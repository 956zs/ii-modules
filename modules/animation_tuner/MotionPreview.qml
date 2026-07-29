import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root

    property var baselineMotion: ({ durationMs: 200, delayMs: 0, bezierCurve: [0.2, 0, 0, 1, 1, 1] })
    property var draft: baselineMotion
    property var springLab: ({ mass: 1, spring: 2.5, damping: 0.3, epsilon: 0.01, velocity: 0, modulus: 0, delayMs: 0 })
    property bool reducedMotion: false
    property bool compareBaseline: true
    property string scenario: "move"
    property bool springAtEnd: false
    property bool resettingSpring: false
    readonly property string draftPreviewSignature: JSON.stringify({
        durationMs: root.draft.durationMs,
        delayMs: root.draft.delayMs,
        bezierCurve: root.draft.bezierCurve
    })
    readonly property string baselinePreviewSignature: JSON.stringify({
        durationMs: root.baselineMotion.durationMs,
        bezierCurve: root.baselineMotion.bezierCurve
    })

    spacing: 8

    function restart() {
        baselineAnimation.stop()
        draftAnimation.stop()
        springDelay.stop()
        baselineMarker.progress = 0
        draftMarker.progress = 0
        root.resettingSpring = true
        root.springAtEnd = false
        root.resettingSpring = false
        if (root.reducedMotion) {
            baselineMarker.progress = 1
            draftMarker.progress = 1
            root.springAtEnd = true
            return
        }
        if (root.compareBaseline) baselineAnimation.start()
        draftAnimation.start()
        springDelay.restart()
    }

    onDraftPreviewSignatureChanged: previewRestart.restart()
    onBaselinePreviewSignatureChanged: previewRestart.restart()
    onSpringLabChanged: previewRestart.restart()
    onReducedMotionChanged: previewRestart.restart()
    onScenarioChanged: previewRestart.restart()
    onCompareBaselineChanged: previewRestart.restart()

    Timer {
        id: previewRestart
        interval: 50
        repeat: false
        onTriggered: root.restart()
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        ConfigSelectionArray {
            Layout.fillWidth: true
            currentValue: root.scenario
            onSelected: value => root.scenario = value
            options: [
                { displayName: Translation.tr("Move"), icon: "open_with", value: "move" },
                { displayName: Translation.tr("Resize"), icon: "aspect_ratio", value: "resize" },
                { displayName: Translation.tr("Fade"), icon: "opacity", value: "fade" },
            ]
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8

            ConfigSwitch {
                text: Translation.tr("Compare baseline")
                buttonIcon: "compare"
                checked: root.compareBaseline
                onCheckedChanged: root.compareBaseline = checked
            }
            RippleButton {
                buttonText: Translation.tr("Replay")
                onClicked: root.restart()
            }
        }
    }

    Rectangle {
        id: stage
        Layout.fillWidth: true
        Layout.preferredHeight: 150
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        component PreviewMarker: Rectangle {
            id: marker
            required property int lane
            property real progress: 0
            property bool baselineLane: false

            readonly property real travel: Math.max(0, stage.width - width - 40)
            x: root.scenario === "move" ? 20 + progress * travel : 20 + lane * 70
            y: 24 + lane * 58
            width: root.scenario === "resize" ? 52 + progress * 48 : 52
            height: root.scenario === "resize" ? 32 + progress * 20 : 40
            radius: Appearance.rounding.small
            color: baselineLane ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
            opacity: root.scenario === "fade" ? 0.15 + progress * 0.85 : 1

            StyledText {
                anchors.centerIn: parent
                text: marker.baselineLane ? Translation.tr("Stock") : Translation.tr("Draft")
                color: marker.baselineLane ? Appearance.colors.colOnTertiary : Appearance.colors.colOnPrimary
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }

        PreviewMarker {
            id: baselineMarker
            lane: 0
            baselineLane: true
            visible: root.compareBaseline
        }
        PreviewMarker {
            id: draftMarker
            lane: 1
        }

        NumberAnimation {
            id: baselineAnimation
            target: baselineMarker
            property: "progress"
            from: 0
            to: 1
            duration: Math.max(0, root.baselineMotion.durationMs ?? 200)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.baselineMotion.bezierCurve ?? [0.2, 0, 0, 1, 1, 1]
        }
        SequentialAnimation {
            id: draftAnimation
            PauseAnimation { duration: Math.max(0, root.draft.delayMs ?? 0) }
            NumberAnimation {
                target: draftMarker
                property: "progress"
                from: 0
                to: 1
                duration: Math.max(0, root.draft.durationMs ?? 200)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.draft.bezierCurve ?? [0.2, 0, 0, 1, 1, 1]
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Spring Lab (preview only)")
        color: Appearance.colors.colOnSecondaryContainer
        font.weight: Font.DemiBold
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Translation.tr("These controls drive a real Qt SpringAnimation preview. The current shell keeps spring animations inline, so this module does not apply them globally.")
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1

        Rectangle {
            id: springMarker
            width: 34
            height: 34
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary
            anchors.verticalCenter: parent.verticalCenter
            x: root.springAtEnd ? parent.width - width - 12 : 12

            Behavior on x {
                enabled: !root.resettingSpring && !root.reducedMotion
                SpringAnimation {
                    mass: root.springLab.mass ?? 1
                    spring: root.springLab.spring ?? 2.5
                    damping: root.springLab.damping ?? 0.3
                    epsilon: root.springLab.epsilon ?? 0.01
                    velocity: root.springLab.velocity ?? 0
                    modulus: root.springLab.modulus ?? 0
                }
            }
        }
    }

    Timer {
        id: springDelay
        interval: Math.max(0, root.springLab.delayMs ?? 0)
        repeat: false
        onTriggered: root.springAtEnd = true
    }
}
