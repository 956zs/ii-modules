import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/*
 * Single-series line chart (Canvas) for the 30-day daily curve. Dataviz
 * specs: 2px line with round joins/caps, area fill as a ~10% wash of the
 * series hue, ≥8px end marker with a 2px surface ring, hairline baseline.
 * Hover shows a crosshair hairline plus a readout line above the plot;
 * sparse x labels wear text tokens.
 */
Item {
    id: root
    property list<real> values: []
    property color lineColor: Appearance.colors.colPrimary
    // The chart's background, for the marker ring.
    property color surfaceColor: Appearance.m3colors.m3surfaceContainer
    property real chartHeight: 84
    property var xLabels: []          // [{i, text}]
    property var hoverLabel: null     // (index, value) => string
    property string defaultLabel: ""

    readonly property int hoveredIndex: mouse.containsMouse && root.values.length > 1
        ? Math.max(0, Math.min(root.values.length - 1,
            Math.round((mouse.mouseX - 6) / ((canvas.width - 12) / (root.values.length - 1)))))
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

        // 6px horizontal inset so the ≥8px end marker isn't clipped at the
        // edges.
        function ptX(i) {
            return 6 + i * ((width - 12) / (root.values.length - 1))
        }
        function ptY(v) {
            return (height - 5) - (Math.max(0, v) / root.maxValue) * (height - 10)
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const n = root.values.length
            const baseY = height - 1

            ctx.strokeStyle = Appearance.colors.colOutlineVariant
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, baseY + 0.5)
            ctx.lineTo(width, baseY + 0.5)
            ctx.stroke()

            if (n < 2)
                return

            // area wash
            ctx.beginPath()
            ctx.moveTo(0, baseY)
            for (let i = 0; i < n; i++)
                ctx.lineTo(ptX(i), ptY(root.values[i]))
            ctx.lineTo(width, baseY)
            ctx.closePath()
            const c = root.lineColor
            ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.1)
            ctx.fill()

            // hover crosshair under the line
            if (root.hoveredIndex >= 0) {
                ctx.strokeStyle = Appearance.colors.colOutlineVariant
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(ptX(root.hoveredIndex) + 0.5, 0)
                ctx.lineTo(ptX(root.hoveredIndex) + 0.5, baseY)
                ctx.stroke()
            }

            // the line
            ctx.strokeStyle = root.lineColor
            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.beginPath()
            for (let i = 0; i < n; i++) {
                if (i === 0)
                    ctx.moveTo(ptX(i), ptY(root.values[i]))
                else
                    ctx.lineTo(ptX(i), ptY(root.values[i]))
            }
            ctx.stroke()

            // end marker (hovered point takes over), 2px surface ring
            const mi = root.hoveredIndex >= 0 ? root.hoveredIndex : n - 1
            ctx.beginPath()
            ctx.arc(ptX(mi), ptY(root.values[mi]), 6, 0, 2 * Math.PI)
            ctx.fillStyle = root.surfaceColor
            ctx.fill()
            ctx.beginPath()
            ctx.arc(ptX(mi), ptY(root.values[mi]), 4, 0, 2 * Math.PI)
            ctx.fillStyle = root.lineColor
            ctx.fill()
        }

        Connections {
            target: root
            function onValuesChanged() { canvas.requestPaint() }
            function onLineColorChanged() { canvas.requestPaint() }
            function onSurfaceColorChanged() { canvas.requestPaint() }
            function onHoveredIndexChanged() { canvas.requestPaint() }
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
                readonly property real stepW: root.values.length > 1 ? labelRow.width / (root.values.length - 1) : 0
                x: Math.max(0, Math.min(labelRow.width - width, modelData.i * stepW - width / 2))
                anchors.top: parent.top
                anchors.topMargin: 2
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: modelData.text
            }
        }
    }
}
