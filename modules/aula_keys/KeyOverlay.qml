import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.aula_keys
import "AulaKeysLogic.js" as Logic

/*
 * Click-through layer-shell overlay: one keycap per configured key with a
 * live travel fill (depth / max_mm), the actuation point as a tick, the
 * key's press count underneath, and a KPS / peak / total line. Never takes
 * input: the empty mask passes every click to the window below.
 */
PanelWindow {
    id: root

    required property KeyFeed feed
    property string corner: "bottomRight"
    property int marginPx: 24
    property real uiScale: 1
    property real contentOpacity: 0.9
    property bool showCounts: true
    property bool showStats: true

    readonly property bool atTop: root.corner.startsWith("top")
    readonly property bool atLeft: root.corner.endsWith("Left")
    readonly property bool atRight: root.corner.endsWith("Right")
    readonly property real capSize: 52 * root.uiScale

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:iimp-aula-keys"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    anchors.top: root.atTop
    anchors.bottom: !root.atTop
    anchors.left: root.atLeft
    anchors.right: root.atRight
    margins {
        top: root.marginPx
        bottom: root.marginPx
        left: root.marginPx
        right: root.marginPx
    }

    implicitWidth: panel.implicitWidth
    implicitHeight: panel.implicitHeight

    Rectangle {
        id: panel
        anchors.fill: parent
        implicitWidth: column.implicitWidth + 2 * pad
        implicitHeight: column.implicitHeight + 2 * pad
        readonly property real pad: 10 * root.uiScale
        opacity: root.contentOpacity
        radius: Appearance.rounding.normal * root.uiScale
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: 6 * root.uiScale

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8 * root.uiScale

                Repeater {
                    model: root.feed.model

                    delegate: Column {
                        id: keyItem
                        required property string label
                        required property real mm
                        required property real point
                        required property bool pressed
                        required property int count
                        required property bool known
                        spacing: 4 * root.uiScale

                        Rectangle {
                            id: cap
                            width: root.capSize
                            height: root.capSize
                            radius: Appearance.rounding.small * root.uiScale
                            clip: true
                            color: Appearance.colors.colLayer2
                            border.width: Math.max(1, 2 * root.uiScale)
                            border.color: keyItem.pressed ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            opacity: keyItem.known || root.feed.status !== "" ? 1 : 0.6

                            // Travel fill grows downward with the key.
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: parent.height * Logic.travelFraction(keyItem.mm, root.feed.maxMm)
                                color: Appearance.colors.colPrimary
                                opacity: keyItem.pressed ? 0.6 : 0.35
                            }

                            // Actuation point tick.
                            Rectangle {
                                visible: keyItem.point > 0 && root.feed.maxMm > 0
                                x: 0
                                width: parent.width
                                height: Math.max(1, 2 * root.uiScale)
                                y: parent.height * Logic.travelFraction(keyItem.point, root.feed.maxMm) - height / 2
                                color: Appearance.colors.colTertiary
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: keyItem.label
                                textFormat: Text.PlainText
                                font.pixelSize: Appearance.font.pixelSize.large * root.uiScale
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                            }
                        }

                        StyledText {
                            visible: root.showCounts
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: String(keyItem.count)
                            font.family: Appearance.font.family.numbers
                            font.features: ({ "tnum": 1 })
                            font.pixelSize: Appearance.font.pixelSize.smaller * root.uiScale
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
            }

            StyledText {
                visible: root.showStats
                Layout.alignment: Qt.AlignHCenter
                font.family: Appearance.font.family.numbers
                font.features: ({ "tnum": 1 })
                font.pixelSize: Appearance.font.pixelSize.smaller * root.uiScale
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("%1 KPS · peak %2 · total %3").arg(root.feed.kpsNow).arg(root.feed.peak).arg(root.feed.total)
            }

            StyledText {
                visible: text !== ""
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: Math.max(160 * root.uiScale, column.width)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smallest * root.uiScale
                color: Appearance.colors.colSubtext
                text: {
                    switch (root.feed.status) {
                    case "starting":
                        return Translation.tr("Connecting…");
                    case "waiting":
                        return Translation.tr("Waiting for the keyboard");
                    case "busy":
                        return Translation.tr("Keyboard busy (aulactl or aula-gui is using it)");
                    case "lost":
                        return Translation.tr("Keyboard disconnected");
                    case "error":
                        return Translation.tr("Feed error: %1").arg(root.feed.errorText);
                    case "restarting":
                        return Translation.tr("Feed stopped, retrying");
                    default:
                        return "";
                    }
                }
            }
        }
    }
}
