import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "AulaKeysLogic.js" as Logic

/*
 * One keycap. Travel is drawn either as a fill rising from the bottom,
 * clipped to the cap's rounded shape with an accent gradient that fades in
 * from the fill's top edge, or as a
 * slim bar on the right edge. The actuation point is a short low-contrast
 * notch on the side edges, never across the legend. Travel is smoothed by
 * a short animation; the pressed state (accent border, brighter cap)
 * switches instantly.
 */
Item {
    id: cap

    property string label: ""
    property real mm: 0
    property real point: 0
    property bool pressed: false
    property real maxMm: 0
    property real uiScale: 1
    // "fill", "bar" or "off" (Logic.normalizeTravelStyle).
    property string travelStyle: "fill"

    readonly property real fraction: Logic.travelFraction(cap.mm, cap.maxMm)
    readonly property real pointFraction: Logic.travelFraction(cap.point, cap.maxMm)
    readonly property bool hasPoint: cap.point > 0 && cap.maxMm > 0 && cap.travelStyle !== "off"
    readonly property real radius: Appearance.rounding.small * cap.uiScale
    readonly property real borderWidth: Math.max(1, (cap.pressed ? 2 : 1) * cap.uiScale)
    readonly property real inner: cap.height - 2 * cap.borderWidth
    readonly property color accent: Appearance.colors.colPrimary
    readonly property color baseColor: cap.pressed ? Qt.tint(Appearance.colors.colLayer2, Qt.rgba(cap.accent.r, cap.accent.g, cap.accent.b, 0.14)) : Appearance.colors.colLayer2

    // Smoothed travel; presses stay instant because they drive colours and
    // the border, not this value.
    property real shownFraction: cap.fraction
    Behavior on shownFraction {
        NumberAnimation {
            duration: 40
            easing.type: Easing.OutQuad
        }
    }

    function accentAlpha(alpha) {
        return Qt.rgba(cap.accent.r, cap.accent.g, cap.accent.b, alpha);
    }

    Rectangle {
        anchors.fill: parent
        radius: cap.radius
        color: cap.baseColor
    }

    // Fill style: a full-size rounded gradient shape revealed from the
    // bottom by a clipping item, so the fill keeps the cap's corners and has
    // no edge line of its own.
    Item {
        visible: cap.travelStyle === "fill"
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: cap.borderWidth
        }
        height: cap.inner * cap.shownFraction
        clip: true

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: cap.inner
            radius: Math.max(0, cap.radius - cap.borderWidth)
            // The gradient starts at the fill's top edge (everything above
            // is clipped away), so the fill fades in instead of ending in a
            // hard line.
            gradient: Gradient {
                GradientStop {
                    position: 1 - cap.shownFraction
                    color: cap.accentAlpha(Logic.fillAlpha(0, cap.pressed))
                }
                GradientStop {
                    position: 1
                    color: cap.accentAlpha(Logic.fillAlpha(1, cap.pressed))
                }
            }
        }
    }

    // Bar style: slim track on the right edge filling from the bottom.
    Rectangle {
        id: track
        visible: cap.travelStyle === "bar"
        width: Math.max(2, 3 * cap.uiScale)
        radius: width / 2
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            rightMargin: cap.borderWidth + 4 * cap.uiScale
            topMargin: cap.borderWidth + 6 * cap.uiScale
            bottomMargin: cap.borderWidth + 6 * cap.uiScale
        }
        color: cap.accentAlpha(0.12)

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            radius: parent.radius
            height: parent.height * cap.shownFraction
            color: cap.accentAlpha(cap.pressed ? 0.95 : 0.6)
        }
    }

    // Actuation notches. Fill style: both side edges at the depth's height.
    // Bar style: one notch left of the track.
    Repeater {
        model: cap.hasPoint ? (cap.travelStyle === "bar" ? ["bar"] : ["left", "right"]) : []

        delegate: Rectangle {
            required property string modelData
            readonly property real span: modelData === "bar" ? track.height : cap.inner
            readonly property real origin: modelData === "bar" ? track.y : cap.borderWidth
            width: Math.max(3, 4 * cap.uiScale)
            height: Math.max(1, 1.5 * cap.uiScale)
            radius: height / 2
            x: modelData === "left" ? cap.borderWidth : modelData === "right" ? cap.width - cap.borderWidth - width : track.x - width - 1.5 * cap.uiScale
            y: origin + span * (1 - cap.pointFraction) - height / 2
            color: Appearance.colors.colOutline
            opacity: 0.8
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: cap.radius
        color: "transparent"
        border.width: cap.borderWidth
        border.color: cap.pressed ? cap.accent : Appearance.colors.colOutlineVariant
    }

    StyledText {
        anchors.centerIn: parent
        text: cap.label
        textFormat: Text.PlainText
        font.pixelSize: Appearance.font.pixelSize.large * cap.uiScale
        font.weight: Font.DemiBold
        // Whichever of the two theme tones reads better over what is behind
        // the legend (bare cap, or cap plus fill once it passes the centre).
        color: Logic.pickContrast(Logic.legendBackdrop(cap.baseColor, cap.accent, cap.travelStyle === "fill" ? cap.shownFraction : 0, cap.pressed), Appearance.colors.colOnLayer2, Appearance.colors.colLayer2) === 0 ? Appearance.colors.colOnLayer2 : Appearance.colors.colLayer2
    }
}
