import QtQuick
import qs.modules.common

/*
 * Tiny time-aware sparkline for the bar pill: battery % over the last N
 * seconds. X is wall-clock time (a 10-minute burst does not stretch to fill
 * the frame), the line breaks across suspend gaps instead of drawing a false
 * flat segment, and charging stretches are tinted with the accent colour.
 *
 * Y is a padded min..max window with a minimum span of 8 pp — a full 0..100
 * axis would flatten a normal afternoon into a straight line, while unpadded
 * min..max would amplify sensor noise into drama.
 */
Item {
    id: root

    // [[t, pct, w, cls]] — BatteryLogic raw slice.
    property var samples: []
    property int windowSec: 3 * 3600
    property int gapSec: 300
    property color lineColor: Appearance.colors.colOnLayer1
    property color chargeColor: Appearance.colors.colPrimary
    property real lineWidth: 1.5

    onSamplesChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onChargeColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const s = root.samples
            if (!s || s.length < 2)
                return

            const t1 = s[s.length - 1][0]
            const t0 = t1 - root.windowSec
            let mn = 100, mx = 0
            for (let i = 0; i < s.length; i++) {
                mn = Math.min(mn, s[i][1])
                mx = Math.max(mx, s[i][1])
            }
            const pad = Math.max(1, (mx - mn) * 0.1)
            mn = Math.max(0, mn - pad)
            mx = Math.min(100, mx + pad)
            if (mx - mn < 8) {
                const c = (mx + mn) / 2
                mn = Math.max(0, c - 4)
                mx = Math.min(100, mn + 8)
            }

            const xOf = t => (t - t0) / (t1 - t0) * (width - 1) + 0.5
            const yOf = p => 1 + (height - 2) * (1 - (p - mn) / (mx - mn))

            ctx.lineWidth = root.lineWidth
            ctx.lineJoin = "round"
            ctx.lineCap = "round"

            // One stroke per contiguous same-colour run; gaps end the run.
            let runColor = null
            let started = false
            for (let i = 0; i < s.length; i++) {
                const p = s[i]
                const col = p[3] === 1 ? root.chargeColor : root.lineColor
                const gap = i > 0 && p[0] - s[i - 1][0] > root.gapSec
                if (!started || gap || col !== runColor) {
                    if (started)
                        ctx.stroke()
                    ctx.beginPath()
                    ctx.strokeStyle = col
                    runColor = col
                    if (!gap && i > 0)
                        ctx.moveTo(xOf(s[i - 1][0]), yOf(s[i - 1][1]))
                    else
                        ctx.moveTo(xOf(p[0]), yOf(p[1]))
                    started = true
                }
                ctx.lineTo(xOf(p[0]), yOf(p[1]))
            }
            if (started)
                ctx.stroke()
        }
    }
}
