import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * 24 h battery curve for the detail panel. Fixed 0..100 axis (the reference
 * frame matters here — "was I above half all day?"), recessive gridlines,
 * hour labels, charging stretches stroked+filled with the accent colour,
 * discharging in neutral ink. Suspend/off gaps get a faint hatch band and no
 * line — a flat connector would claim knowledge the sampler does not have.
 *
 * Hover shows a crosshair with time · % · W of the nearest sample.
 */
Item {
    id: root

    // [[t, pct, w, cls]] — BatteryLogic raw (24 h).
    property var samples: []
    property int gapSec: 300
    property color dischargeColor: Appearance.colors.colOnSurfaceVariant
    property color chargeColor: Appearance.colors.colPrimary
    // Set by the parent so the readout can say "14:32 · 76% · 8.4 W".
    property var fmtClock: t => ""

    readonly property int axisPad: 18   // left gutter for y labels
    readonly property int bottomPad: 14 // hour labels

    onSamplesChanged: canvas.requestPaint()
    onDischargeColorChanged: canvas.requestPaint()
    onChargeColorChanged: canvas.requestPaint()

    // Hover state
    property int hoverIdx: -1

    function plotW() { return width - axisPad }
    function plotH() { return height - bottomPad }
    function tRange() {
        const t1 = Math.floor(Date.now() / 1000)
        return [t1 - 86400, t1]
    }
    function xOf(t) {
        const r = tRange()
        return axisPad + (t - r[0]) / (r[1] - r[0]) * (plotW() - 1)
    }
    function yOf(p) {
        return 1 + (plotH() - 2) * (1 - p / 100)
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const s = root.samples
            const r = root.tRange()
            const pw = root.plotW()
            const ph = root.plotH()

            // Grid: 0/25/50/75/100, recessive.
            ctx.lineWidth = 1
            ctx.strokeStyle = ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)
            ctx.fillStyle = Appearance.colors.colOnLayer1Inactive
            ctx.font = `9px ${Appearance.font.family.main}`
            ctx.textAlign = "left"
            for (let g = 0; g <= 100; g += 25) {
                const y = root.yOf(g)
                ctx.beginPath()
                ctx.moveTo(root.axisPad, y)
                ctx.lineTo(width, y)
                ctx.stroke()
                if (g % 50 === 0)
                    ctx.fillText(`${g}`, 0, Math.min(ph - 2, Math.max(8, y + 3)))
            }
            // Hour ticks every 6 h, aligned to local clock hours.
            ctx.textAlign = "center"
            const firstTick = Math.ceil(r[0] / 21600) * 21600
            for (let t = firstTick; t <= r[1]; t += 21600) {
                const d = new Date(t * 1000)
                const hh = (d.getHours() + Math.round(d.getMinutes() / 60)) % 24
                ctx.fillText(`${String(hh).padStart(2, "0")}h`,
                             Math.min(Math.max(root.xOf(t), root.axisPad + 10), width - 11),
                             height - 3)
            }

            if (!s || s.length < 2)
                return

            // Gap bands first (under the line).
            ctx.fillStyle = ColorUtils.transparentize(Appearance.colors.colOnLayer1Inactive, 0.88)
            for (let i = 1; i < s.length; i++) {
                if (s[i][0] - s[i - 1][0] > root.gapSec) {
                    const x0 = root.xOf(s[i - 1][0])
                    const x1 = root.xOf(s[i][0])
                    ctx.fillRect(x0, 1, Math.max(1, x1 - x0), ph - 2)
                }
            }

            ctx.lineWidth = 2
            ctx.lineJoin = "round"
            ctx.lineCap = "round"

            // Stroke contiguous same-class runs; fill charging runs to the
            // baseline so "power went in here" reads at a glance (fill is a
            // second, non-hue encoding for the charging state).
            let run = []
            const flushRun = () => {
                if (run.length < 2) { run = []; return }
                const charging = run[0][3] === 1
                const col = charging ? root.chargeColor : root.dischargeColor
                ctx.strokeStyle = col
                ctx.beginPath()
                ctx.moveTo(root.xOf(run[0][0]), root.yOf(run[0][1]))
                for (let j = 1; j < run.length; j++)
                    ctx.lineTo(root.xOf(run[j][0]), root.yOf(run[j][1]))
                ctx.stroke()
                if (charging) {
                    ctx.fillStyle = ColorUtils.transparentize(col, 0.82)
                    ctx.lineTo(root.xOf(run[run.length - 1][0]), root.yOf(0))
                    ctx.lineTo(root.xOf(run[0][0]), root.yOf(0))
                    ctx.closePath()
                    ctx.fill()
                }
                run = []
            }
            for (let i = 0; i < s.length; i++) {
                const gap = i > 0 && s[i][0] - s[i - 1][0] > root.gapSec
                const clsFlip = run.length > 0
                        && (run[run.length - 1][3] === 1) !== (s[i][3] === 1)
                if (gap) {
                    flushRun()
                } else if (clsFlip) {
                    const bridge = run[run.length - 1]
                    flushRun()
                    run.push(bridge) // runs share the boundary point
                }
                run.push(s[i])
            }
            flushRun()

            // Hover crosshair.
            if (root.hoverIdx >= 0 && root.hoverIdx < s.length) {
                const hs = s[root.hoverIdx]
                const x = root.xOf(hs[0])
                ctx.strokeStyle = ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.5)
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(x, 1)
                ctx.lineTo(x, ph)
                ctx.stroke()
                ctx.fillStyle = hs[3] === 1 ? root.chargeColor : root.dischargeColor
                ctx.beginPath()
                ctx.arc(x, root.yOf(hs[1]), 3, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            const s = root.samples
            if (!s || s.length === 0) return
            const r = root.tRange()
            const t = r[0] + (mouse.x - root.axisPad) / Math.max(1, root.plotW() - 1) * (r[1] - r[0])
            let best = -1, bestD = 1e18
            for (let i = 0; i < s.length; i++) {
                const d = Math.abs(s[i][0] - t)
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

    // Hover readout, top corner away from the cursor half.
    Rectangle {
        visible: root.hoverIdx >= 0 && root.hoverIdx < root.samples.length
        y: 0
        x: {
            if (root.hoverIdx < 0 || root.hoverIdx >= root.samples.length)
                return root.axisPad + 2
            // Dodge the cursor: readout sits in the opposite half.
            return root.xOf(root.samples[root.hoverIdx][0]) > root.width / 2
                    ? root.axisPad + 2 : root.width - width
        }
        color: Appearance.colors.colSurfaceContainerHighest
        radius: 4
        width: readout.implicitWidth + 10
        height: readout.implicitHeight + 6

        Text {
            id: readout
            anchors.centerIn: parent
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurface
            text: {
                if (root.hoverIdx < 0 || root.hoverIdx >= root.samples.length)
                    return ""
                const hs = root.samples[root.hoverIdx]
                const w = hs[2] > 0.05 ? ` · ${hs[2].toFixed(1)} W` : ""
                return `${root.fmtClock(hs[0])} · ${Math.round(hs[1])}%${w}`
            }
        }
    }
}
