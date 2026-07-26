import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Battery health trend: full-charge capacity as % of design capacity, one
 * point per day, up to a year. Warning-toned line (health only degrades;
 * this chart exists to show how fast). Y is padded around the data — health
 * lives in a narrow band (e.g. 58–64 %) and a 0..100 axis would flatten a
 * year of wear into a hairline. The axis labels make the zoom explicit.
 *
 * Endpoints are direct-labeled; hover reads out any day.
 */
Item {
    id: root

    // [[dayStart, healthPct]] — BatteryLogic healthSeries.
    property var series: []
    property color lineColor: Appearance.colors.colError
    property var fmtDay: t => ""

    readonly property int axisPad: 22
    readonly property int bottomPad: 14

    onSeriesChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()

    property int hoverIdx: -1

    function plotW() { return width - axisPad }
    function plotH() { return height - bottomPad }
    function domain() {
        const s = root.series
        let mn = 100, mx = 0
        for (let i = 0; i < s.length; i++) {
            mn = Math.min(mn, s[i][1])
            mx = Math.max(mx, s[i][1])
        }
        mn = Math.max(0, Math.floor((mn - 2) / 5) * 5)
        mx = Math.min(100, Math.ceil((mx + 2) / 5) * 5)
        if (mx - mn < 10) mn = Math.max(0, mx - 10)
        return [mn, mx]
    }
    function tRange() {
        const s = root.series
        if (s.length < 2) return [0, 1]
        // At least a 30-day window so early sparse data does not stretch.
        const span = Math.max(30 * 86400, s[s.length - 1][0] - s[0][0])
        return [s[s.length - 1][0] - span, s[s.length - 1][0]]
    }
    function xOf(t) {
        const r = tRange()
        return axisPad + (t - r[0]) / (r[1] - r[0]) * (plotW() - 6) + 2
    }
    function yOf(p, dom) {
        return 3 + (plotH() - 6) * (1 - (p - dom[0]) / (dom[1] - dom[0]))
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const s = root.series
            if (!s || s.length < 2)
                return
            const dom = root.domain()
            const ph = root.plotH()

            ctx.lineWidth = 1
            ctx.strokeStyle = ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)
            ctx.fillStyle = Appearance.colors.colOnLayer1Inactive
            ctx.font = `9px ${Appearance.font.family.main}`
            ctx.textAlign = "left"
            for (let g = dom[0]; g <= dom[1]; g += 5) {
                const y = root.yOf(g, dom)
                ctx.beginPath()
                ctx.moveTo(root.axisPad, y)
                ctx.lineTo(width, y)
                ctx.stroke()
                ctx.fillText(`${g}`, 0, Math.min(ph - 2, Math.max(8, y + 3)))
            }
            ctx.textAlign = "center"
            const clampX = x => Math.min(Math.max(x, root.axisPad + 12), width - 13)
            ctx.fillText(root.fmtDay(s[0][0]), clampX(root.xOf(s[0][0])), height - 3)
            ctx.fillText(root.fmtDay(s[s.length - 1][0]), clampX(root.xOf(s[s.length - 1][0])), height - 3)

            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.strokeStyle = root.lineColor
            ctx.beginPath()
            ctx.moveTo(root.xOf(s[0][0]), root.yOf(s[0][1], dom))
            for (let i = 1; i < s.length; i++)
                ctx.lineTo(root.xOf(s[i][0]), root.yOf(s[i][1], dom))
            ctx.stroke()

            if (root.hoverIdx >= 0 && root.hoverIdx < s.length) {
                const hs = s[root.hoverIdx]
                ctx.fillStyle = root.lineColor
                ctx.beginPath()
                ctx.arc(root.xOf(hs[0]), root.yOf(hs[1], dom), 3, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            const s = root.series
            let best = -1, bestD = 1e18
            for (let i = 0; i < s.length; i++) {
                const d = Math.abs(root.xOf(s[i][0]) - mouse.x)
                if (d < bestD) { bestD = d; best = i }
            }
            if (root.hoverIdx !== best) {
                root.hoverIdx = best
                canvas.requestPaint()
            }
        }
        onExited: {
            root.hoverIdx = -1
            canvas.requestPaint()
        }
    }

    Rectangle {
        visible: root.hoverIdx >= 0 && root.hoverIdx < root.series.length
        y: 0
        x: {
            if (root.hoverIdx < 0 || root.hoverIdx >= root.series.length)
                return root.axisPad + 2
            return root.xOf(root.series[root.hoverIdx][0]) > root.width / 2
                    ? root.axisPad + 2 : root.width - width
        }
        color: Appearance.colors.colSurfaceContainerHighest
        radius: 4
        width: healthReadout.implicitWidth + 10
        height: healthReadout.implicitHeight + 6

        Text {
            id: healthReadout
            anchors.centerIn: parent
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurface
            text: root.hoverIdx >= 0 && root.hoverIdx < root.series.length
                  ? `${root.fmtDay(root.series[root.hoverIdx][0])} · ${root.series[root.hoverIdx][1].toFixed(1)}%`
                  : ""
        }
    }
}
