import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/*
 * Single-series column chart (Canvas). Dataviz specs: bars capped at 24px
 * thick with the band's leftover as air, 4px rounded data-end / square
 * baseline, a 2px surface gap between adjacent bars, hairline baseline.
 * One hue for magnitude; an optional highlight index (today / current hour)
 * gets the accent step while the rest wear a lighter step of the same ramp.
 * Values never label every bar — a readout line above the plot carries the
 * hovered value (default text otherwise), labels wear text tokens.
 */
Item {
    id: root
    property list<real> values: []
    // Optional presence mask distinguishes missing observations from a real 0.
    // Empty means every value is observed.
    property var present: []
    // Optional horizontal reference line, e.g. a period average.
    property real referenceValue: -1
    property int highlightIndex: -1
    // highlight -> accent, rest -> dim (lighter step of the same ramp).
    // With no highlight every bar is accent.
    property color accentColor: Appearance.colors.colPrimary
    property color dimColor: Appearance.colors.colPrimaryContainer
    property real maxBarWidth: 24
    property real chartHeight: 84
    // [{i, text}] sparse x-axis labels
    property var xLabels: []
    // (index, value) => readout string while hovering
    property var hoverLabel: null
    property string defaultLabel: ""

    readonly property int hoveredIndex: mouse.containsMouse && root.values.length > 0
        ? Math.max(0, Math.min(root.values.length - 1,
            Math.floor(mouse.mouseX / (canvas.width / root.values.length))))
        : -1
    readonly property real maxValue: Math.max(1, ...root.values)

    implicitHeight: readout.implicitHeight + 4 + root.chartHeight + labelRow.height

    StyledText {
        id: readout
        anchors.left: parent.left
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: (root.hoveredIndex >= 0 && root.hoverLabel)
              ? root.hoverLabel(root.hoveredIndex, root.values[root.hoveredIndex])
              : root.defaultLabel
    }

    Canvas {
        id: canvas
        anchors.top: readout.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.chartHeight

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const n = root.values.length
            if (n === 0)
                return
            const slot = width / n
            const barW = Math.min(root.maxBarWidth, Math.max(2, slot - 2))
            const baseY = height - 1

            // hairline baseline, recessive
            ctx.strokeStyle = Appearance.colors.colOutlineVariant
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, baseY + 0.5)
            ctx.lineTo(width, baseY + 0.5)
            ctx.stroke()

            for (let i = 0; i < n; i++) {
                const observed = root.present.length === 0 || root.present[i] === true
                const v = Math.max(0, Number(root.values[i]) || 0)
                const x = i * slot + (slot - barW) / 2
                if (!observed) {
                    ctx.fillStyle = Appearance.colors.colLayer2
                    ctx.fillRect(x, baseY - 2, barW, 2)
                    continue
                }
                if (v <= 0)
                    continue
                const h = Math.max(2, (v / root.maxValue) * (height - 6))
                const y = baseY - h
                const r = Math.min(4, barW / 2, h)
                ctx.fillStyle = (root.highlightIndex < 0 || i === root.highlightIndex)
                                ? root.accentColor : root.dimColor
                // rounded data-end, square at the baseline
                ctx.beginPath()
                ctx.moveTo(x, baseY)
                ctx.lineTo(x, y + r)
                ctx.arcTo(x, y, x + r, y, r)
                ctx.lineTo(x + barW - r, y)
                ctx.arcTo(x + barW, y, x + barW, y + r, r)
                ctx.lineTo(x + barW, baseY)
                ctx.closePath()
                ctx.fill()
            }

            if (root.referenceValue >= 0 && root.maxValue > 0) {
                const y = baseY - Math.min(1, root.referenceValue / root.maxValue) * (height - 6)
                ctx.strokeStyle = Appearance.colors.colOnSurfaceVariant
                ctx.lineWidth = 1
                ctx.setLineDash([4, 3])
                ctx.beginPath()
                ctx.moveTo(0, y + 0.5)
                ctx.lineTo(width, y + 0.5)
                ctx.stroke()
                ctx.setLineDash([])
            }
        }

        Connections {
            target: root
            function onValuesChanged() { canvas.requestPaint() }
            function onPresentChanged() { canvas.requestPaint() }
            function onReferenceValueChanged() { canvas.requestPaint() }
            function onHighlightIndexChanged() { canvas.requestPaint() }
            function onAccentColorChanged() { canvas.requestPaint() }
            function onDimColorChanged() { canvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        // The panel window is created hidden; the canvas only becomes
        // paintable once the surface maps.
        onAvailableChanged: if (available) requestPaint()

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }

    Item {
        id: labelRow
        anchors.top: canvas.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: (root.xLabels?.length ?? 0) > 0 ? 16 : 0

        Repeater {
            model: root.xLabels
            delegate: StyledText {
                required property var modelData
                readonly property real slotW: root.values.length > 0 ? labelRow.width / root.values.length : 0
                x: Math.max(0, Math.min(labelRow.width - width,
                    (modelData.i + 0.5) * slotW - width / 2))
                anchors.top: parent.top
                anchors.topMargin: 2
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: modelData.text
            }
        }
    }
}
