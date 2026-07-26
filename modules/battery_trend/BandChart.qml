import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * 30-day daily range chart: one thin rounded column per day spanning that
 * day's min..max battery %, with a 2 px tick at the daily average. Fixed
 * 0..100 axis. A wide pale column = the battery swung a lot that day; a
 * short one high up = it barely left the charger.
 *
 * Hover reads out "7/12 · 45–98% · avg 71%".
 */
Item {
    id: root

    // [[dayStart, min, max, avg]] — BatteryLogic bandDays (≤ 31 entries).
    property var days: []
    property color bandColor: Appearance.colors.colSecondaryContainer
    property color avgColor: Appearance.colors.colSecondary
    property var fmtDay: t => ""

    readonly property int axisPad: 18
    readonly property int bottomPad: 14

    onDaysChanged: canvas.requestPaint()
    onBandColorChanged: canvas.requestPaint()

    property int hoverIdx: -1

    function plotW() { return width - axisPad }
    function plotH() { return height - bottomPad }
    function slotW() { return plotW() / 31 }
    function xOf(i) { return axisPad + (i + 0.5) * slotW() }
    function yOf(p) { return 1 + (plotH() - 2) * (1 - p / 100) }
    // Day slots are positional from the left = oldest shown day.
    function idxOf(entry) {
        const d = root.days
        if (d.length === 0) return 0
        const last = d[d.length - 1][0]
        return 30 - Math.round((last - entry[0]) / 86400)
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const d = root.days
            const ph = root.plotH()

            ctx.lineWidth = 1
            ctx.strokeStyle = ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)
            ctx.fillStyle = Appearance.colors.colOnLayer1Inactive
            ctx.font = `9px ${Appearance.font.family.main}`
            ctx.textAlign = "left"
            for (let g = 0; g <= 100; g += 50) {
                const y = root.yOf(g)
                ctx.beginPath()
                ctx.moveTo(root.axisPad, y)
                ctx.lineTo(width, y)
                ctx.stroke()
                ctx.fillText(`${g}`, 0, Math.min(ph - 2, Math.max(8, y + 3)))
            }
            if (!d || d.length === 0)
                return

            const bw = Math.max(3, root.slotW() - 2)
            ctx.textAlign = "center"
            for (let i = 0; i < d.length; i++) {
                const slot = root.idxOf(d[i])
                if (slot < 0 || slot > 30) continue
                const x = root.xOf(slot)
                const yTop = root.yOf(d[i][2])
                const yBot = root.yOf(d[i][1])
                const hovered = i === root.hoverIdx
                ctx.fillStyle = hovered
                        ? ColorUtils.transparentize(root.bandColor, 0)
                        : ColorUtils.transparentize(root.bandColor, 0.25)
                roundRect(ctx, x - bw / 2, yTop, bw, Math.max(3, yBot - yTop), 2)
                ctx.fill()
                // Average tick: second encoding on top of the band.
                ctx.fillStyle = root.avgColor
                ctx.fillRect(x - bw / 2, root.yOf(d[i][3]) - 1, bw, 2)
                // Date label roughly weekly, always on the newest day.
                if (slot === 30 || (30 - slot) % 7 === 0) {
                    ctx.fillStyle = Appearance.colors.colOnLayer1Inactive
                    // Clamp so the newest label is not clipped at the edge.
                    ctx.fillText(root.fmtDay(d[i][0]),
                                 Math.min(Math.max(x, root.axisPad + 12), width - 13),
                                 height - 3)
                }
            }
        }

        function roundRect(ctx, x, y, w, h, r) {
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            const d = root.days
            let best = -1, bestD = 1e18
            for (let i = 0; i < d.length; i++) {
                const dist = Math.abs(root.xOf(root.idxOf(d[i])) - mouse.x)
                if (dist < bestD) { bestD = dist; best = i }
            }
            if (bestD > root.slotW()) best = -1
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
        visible: root.hoverIdx >= 0 && root.hoverIdx < root.days.length
        y: 0
        x: {
            if (root.hoverIdx < 0 || root.hoverIdx >= root.days.length)
                return root.axisPad + 2
            return root.xOf(root.idxOf(root.days[root.hoverIdx])) > root.width / 2
                    ? root.axisPad + 2 : root.width - width
        }
        color: Appearance.colors.colSurfaceContainerHighest
        radius: 4
        width: bandReadout.implicitWidth + 10
        height: bandReadout.implicitHeight + 6

        Text {
            id: bandReadout
            anchors.centerIn: parent
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurface
            text: {
                if (root.hoverIdx < 0 || root.hoverIdx >= root.days.length)
                    return ""
                const e = root.days[root.hoverIdx]
                return `${root.fmtDay(e[0])} · ${Math.round(e[1])}–${Math.round(e[2])}% · ⌀ ${Math.round(e[3])}%`
            }
        }
    }
}
