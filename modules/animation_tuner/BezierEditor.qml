import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.mod.animation_tuner
import qs.services
import "MotionMath.js" as MotionMath

ColumnLayout {
    id: root

    property var curve: [0.2, 0, 0, 1, 1, 1]
    property var baselineCurve: []
    property real minimumY: -2
    property real maximumY: 3
    readonly property int segmentCount: Math.floor(curve.length / 6)

    signal curveEdited(var curve)

    spacing: 8

    function copyCurve() {
        return Array.from(root.curve)
    }

    function pointModel() {
        const points = []
        for (let segment = 0; segment < root.segmentCount; ++segment) {
            const offset = segment * 6
            points.push({ index: offset, segment, kind: "c1", x: root.curve[offset], y: root.curve[offset + 1] })
            points.push({ index: offset + 2, segment, kind: "c2", x: root.curve[offset + 2], y: root.curve[offset + 3] })
            if (segment < root.segmentCount - 1)
                points.push({ index: offset + 4, segment, kind: "end", x: root.curve[offset + 4], y: root.curve[offset + 5] })
        }
        return points
    }

    function segmentBounds(segment) {
        const startX = segment === 0 ? 0 : root.curve[segment * 6 - 2]
        const endX = root.curve[segment * 6 + 4]
        return { startX, endX }
    }

    function updatePoint(index, x, y) {
        const next = root.copyCurve()
        const segment = Math.floor(index / 6)
        const kindOffset = index % 6
        const bounds = root.segmentBounds(segment)
        let minX = bounds.startX
        let maxX = bounds.endX
        if (kindOffset === 4) {
            const previous = segment === 0 ? 0 : next[index - 6]
            const following = next[index + 6]
            minX = previous + 0.01
            maxX = following - 0.01
        }
        next[index] = Math.max(minX, Math.min(maxX, x))
        next[index + 1] = Math.max(root.minimumY, Math.min(root.maximumY, y))
        if (kindOffset === 4) {
            next[index - 2] = Math.min(next[index], next[index - 2])
            next[index + 2] = Math.max(next[index], next[index + 2])
        }
        root.curveEdited(next)
    }

    function adjustPoint(index, dx, dy) {
        root.updatePoint(index, root.curve[index] + dx, root.curve[index + 1] + dy)
    }

    function addSegment() {
        if (root.segmentCount >= 4) return
        const next = root.copyCurve()
        const previousEnd = next.length === 0 ? 0 : next[next.length - 2]
        const previousY = next.length === 0 ? 0 : next[next.length - 1]
        if (next.length >= 6) {
            const oldOffset = next.length - 6
            const splitX = (previousEnd + (oldOffset === 0 ? 0 : next[oldOffset - 2])) / 2
            const splitY = previousY / 2
            next[oldOffset + 2] = Math.min(splitX, next[oldOffset + 2])
            next[oldOffset + 4] = splitX
            next[oldOffset + 5] = splitY
            next.push(splitX + (1 - splitX) / 3, splitY, splitX + 2 * (1 - splitX) / 3, 1, 1, 1)
        } else {
            next.push(0.2, 0, 0.8, 1, 1, 1)
        }
        root.curveEdited(next)
    }

    function removeSegment() {
        if (root.segmentCount <= 1) return
        const next = root.copyCurve()
        next.splice(next.length - 6, 6)
        next[next.length - 2] = 1
        next[next.length - 1] = 1
        root.curveEdited(next)
    }

    Rectangle {
        id: plot
        Layout.fillWidth: true
        Layout.preferredHeight: 250
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        readonly property real padding: 20
        readonly property real plotWidth: width - padding * 2
        readonly property real plotHeight: height - padding * 2

        function mapX(value) {
            return padding + value * plotWidth
        }
        function mapY(value) {
            return padding + (root.maximumY - value) / (root.maximumY - root.minimumY) * plotHeight
        }
        function unmapX(value) {
            return (value - padding) / plotWidth
        }
        function unmapY(value) {
            return root.maximumY - (value - padding) / plotHeight * (root.maximumY - root.minimumY)
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative

            onAvailableChanged: if (available) requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            function drawCurve(context, curve, color, baseline) {
                const samples = MotionMath.sampleBezier(curve, 100)
                if (samples.length === 0) return
                context.beginPath()
                context.strokeStyle = color
                context.globalAlpha = baseline ? 0.8 : 1
                context.lineWidth = 2
                context.moveTo(plot.mapX(samples[0].x), plot.mapY(samples[0].y))
                for (let i = 1; i < samples.length; ++i)
                    context.lineTo(plot.mapX(samples[i].x), plot.mapY(samples[i].y))
                context.stroke()
                if (baseline) {
                    context.fillStyle = color
                    for (let i = 0; i < samples.length; i += 10) {
                        context.beginPath()
                        context.arc(plot.mapX(samples[i].x), plot.mapY(samples[i].y), 2, 0, Math.PI * 2)
                        context.fill()
                    }
                }
                context.globalAlpha = 1
            }

            onPaint: {
                const context = getContext("2d")
                context.clearRect(0, 0, width, height)
                context.strokeStyle = Appearance.colors.colOutline
                context.lineWidth = 1
                for (let x = 0; x <= 1; x += 0.25) {
                    context.beginPath()
                    context.moveTo(plot.mapX(x), plot.padding)
                    context.lineTo(plot.mapX(x), plot.height - plot.padding)
                    context.stroke()
                }
                for (let y = -2; y <= 3; ++y) {
                    context.strokeStyle = y === 0 || y === 1
                        ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOutlineVariant
                    context.lineWidth = y === 0 || y === 1 ? 2 : 1
                    context.beginPath()
                    context.moveTo(plot.padding, plot.mapY(y))
                    context.lineTo(plot.width - plot.padding, plot.mapY(y))
                    context.stroke()
                }
                if (root.baselineCurve.length > 0)
                    drawCurve(context, root.baselineCurve, Appearance.colors.colOnSurfaceVariant, true)
                drawCurve(context, root.curve, Appearance.colors.colPrimary, false)

                context.strokeStyle = Appearance.colors.colTertiary
                context.lineWidth = 1
                let startX = 0
                let startY = 0
                for (let segment = 0; segment < root.segmentCount; ++segment) {
                    const offset = segment * 6
                    context.beginPath()
                    context.moveTo(plot.mapX(startX), plot.mapY(startY))
                    context.lineTo(plot.mapX(root.curve[offset]), plot.mapY(root.curve[offset + 1]))
                    context.moveTo(plot.mapX(root.curve[offset + 4]), plot.mapY(root.curve[offset + 5]))
                    context.lineTo(plot.mapX(root.curve[offset + 2]), plot.mapY(root.curve[offset + 3]))
                    context.stroke()
                    startX = root.curve[offset + 4]
                    startY = root.curve[offset + 5]
                }
            }

            Connections {
                target: root
                function onCurveChanged() { canvas.requestPaint() }
                function onBaselineCurveChanged() { canvas.requestPaint() }
            }
        }

        Repeater {
            model: root.pointModel()
            delegate: Rectangle {
                id: handle
                required property var modelData
                required property int index
                property var dragStartCurve: []

                x: plot.mapX(modelData.x) - width / 2
                y: plot.mapY(modelData.y) - height / 2
                width: modelData.kind === "end" ? 16 : 18
                height: width
                radius: width / 2
                color: activeFocus ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
                border.width: 2
                border.color: Appearance.colors.colLayer0
                activeFocusOnTab: true

                Accessible.role: Accessible.Slider
                Accessible.name: Translation.tr("Bezier %1 point for segment %2").arg(modelData.kind).arg(modelData.segment + 1)
                Accessible.description: Translation.tr("Coordinates %1, %2. Use arrow keys to adjust; hold Shift for larger steps")
                    .arg(modelData.x.toFixed(2)).arg(modelData.y.toFixed(2))
                Accessible.onIncreaseAction: root.adjustPoint(modelData.index, 0.01, 0)
                Accessible.onDecreaseAction: root.adjustPoint(modelData.index, -0.01, 0)

                Keys.onPressed: event => {
                    const step = event.modifiers & Qt.ShiftModifier ? 0.1 : 0.01
                    if (event.key === Qt.Key_Left) root.adjustPoint(modelData.index, -step, 0)
                    else if (event.key === Qt.Key_Right) root.adjustPoint(modelData.index, step, 0)
                    else if (event.key === Qt.Key_Up) root.adjustPoint(modelData.index, 0, step)
                    else if (event.key === Qt.Key_Down) root.adjustPoint(modelData.index, 0, -step)
                    else return
                    event.accepted = true
                }

                TapHandler {
                    onTapped: handle.forceActiveFocus()
                }
                DragHandler {
                    id: drag
                    target: null
                    onActiveChanged: if (active) handle.dragStartCurve = root.copyCurve()
                    onTranslationChanged: {
                        if (!active || handle.dragStartCurve.length === 0) return
                        const sourceX = handle.dragStartCurve[handle.modelData.index]
                        const sourceY = handle.dragStartCurve[handle.modelData.index + 1]
                        root.updatePoint(
                            handle.modelData.index,
                            sourceX + translation.x / plot.plotWidth,
                            sourceY - translation.y / plot.plotHeight * (root.maximumY - root.minimumY)
                        )
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Flow {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 18
                height: 2
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: Translation.tr("Draft")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Rectangle {
                width: 18
                height: 1
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: Translation.tr("Stock baseline")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                enabled: root.segmentCount < 4
                buttonText: Translation.tr("Add segment")
                onClicked: root.addSegment()
            }
            RippleButton {
                enabled: root.segmentCount > 1
                buttonText: Translation.tr("Remove segment")
                onClicked: root.removeSegment()
            }
        }
    }

    Repeater {
        model: root.pointModel()
        delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.preferredWidth: 96
                text: Translation.tr("Segment %1 %2").arg(modelData.segment + 1).arg(modelData.kind)
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            MaterialTextField {
                Layout.fillWidth: true
                Accessible.name: Translation.tr("Segment %1 %2 X coordinate").arg(modelData.segment + 1).arg(modelData.kind)
                text: Number(modelData.x).toFixed(3)
                validator: DoubleValidator { bottom: 0; top: 1; decimals: 3 }
                onEditingFinished: {
                    const value = Number(text)
                    if (Number.isFinite(value)) root.updatePoint(modelData.index, value, modelData.y)
                }
            }
            MaterialTextField {
                Layout.fillWidth: true
                Accessible.name: Translation.tr("Segment %1 %2 Y coordinate").arg(modelData.segment + 1).arg(modelData.kind)
                text: Number(modelData.y).toFixed(3)
                validator: DoubleValidator { bottom: root.minimumY; top: root.maximumY; decimals: 3 }
                onEditingFinished: {
                    const value = Number(text)
                    if (Number.isFinite(value)) root.updatePoint(modelData.index, modelData.x, value)
                }
            }
        }
    }
}
