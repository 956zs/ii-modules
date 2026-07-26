import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/*
 * Smooth rate graph: Catmull-Rom spline rendered as cubic beziers, area fill,
 * and a dynamic scale — the window maximum is the top edge and is printed as a
 * small label in the corner, so a 50 KB/s trickle and a 100 MB/s burst both
 * fill the frame legibly.
 *
 * Values are raw bytes/s (unlike stock Graph.qml, which wants pre-normalised
 * 0..1 — normalising outside would lose the max we want to label).
 */
Item {
    id: root

    required property list<real> values
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.35
    property string maxLabel: ""      // set by the parent from the same values

    onValuesChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const vals = root.values
            if (!vals || vals.length < 2)
                return

            const max = Math.max(...vals, 1)
            const n = vals.length
            const dx = width / (n - 1)
            // 1px inset so the stroke isn't clipped at the extremes.
            const yOf = v => 1 + (height - 2) * (1 - v / max)
            const pts = []
            for (let i = 0; i < n; i++)
                pts.push({ x: i * dx, y: yOf(vals[i]) })

            ctx.strokeStyle = root.color
            ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.moveTo(pts[0].x, pts[0].y)
            // Catmull-Rom -> cubic bezier, clamped at the ends.
            for (let i = 0; i < n - 1; i++) {
                const p0 = pts[Math.max(0, i - 1)]
                const p1 = pts[i]
                const p2 = pts[i + 1]
                const p3 = pts[Math.min(n - 1, i + 2)]
                ctx.bezierCurveTo(
                    p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6,
                    p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6,
                    p2.x, p2.y)
            }
            ctx.stroke()
            ctx.lineTo(width, height)
            ctx.lineTo(0, height)
            ctx.closePath()
            ctx.fill()
        }
    }

    StyledText {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: 2
        visible: root.maxLabel.length > 0
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer1Inactive
        text: root.maxLabel
    }
}
