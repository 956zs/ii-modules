import QtQuick
import qs.modules.common

/*
 * Proportional stacked composition bar (part-to-whole). One rounded pill
 * per segment, separated by a consistent 2px of surface showing through —
 * the gap does the separating, no strokes. Values paint left to right and
 * fill the whole width, so the bar is only as honest as the taxonomy fed
 * in (here: in use + reclaimable + free = MemTotal, exact). Zero segments
 * drop out; widths animate on refresh.
 *
 * The Repeater is driven by the segment COUNT, not the array, so delegates
 * survive every poll and the width Behavior actually animates instead of
 * the delegates being recreated.
 */
Item {
    id: root
    // [{ value, color }] painted left → right.
    property var segments: []
    property int gap: 2

    readonly property real total: {
        let t = 0
        for (const s of root.segments)
            t += Math.max(0, s.value)
        return t
    }
    readonly property int visibleCount: {
        let n = 0
        for (const s of root.segments)
            if (root.total > 0 && Math.max(0, s.value) / root.total >= 0.005)
                n++
        return n
    }

    // Empty/unknown data: a single muted track instead of nothing.
    Rectangle {
        anchors.fill: parent
        visible: root.total <= 0
        radius: height / 2
        color: Appearance.colors.colSurfaceContainerHighest
    }

    Row {
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.segments.length

            Rectangle {
                required property int index
                readonly property var seg: root.segments[index]
                readonly property real frac: root.total > 0 ? Math.max(0, seg.value) / root.total : 0

                visible: frac >= 0.005
                width: Math.max(4, (root.width - root.gap * (root.visibleCount - 1)) * frac)
                height: root.height
                radius: height / 2 // Qt clamps for slim segments
                color: seg.color

                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
