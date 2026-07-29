import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/*
 * Weekday x hour heatmap. Rows are Monday..Sunday and cells show the average
 * minutes for that weekday/hour across complete historical days. The mark is
 * sequential: the current Material primary hue grows more opaque as minutes
 * increase; zero remains a neutral surface cell.
 */
Item {
    id: root

    property var values: Array.from({ length: 7 }, () => new Array(24).fill(0))
    property var dayLabels: []
    property var valueLabel: (dow, hour, minutes) => `${dow} ${hour}:00 · ${Math.round(minutes)}m`
    property string defaultLabel: ""
    property real chartHeight: 98
    property color primaryColor: Appearance.colors.colPrimary
    property color surfaceColor: Appearance.colors.colLayer2
    property color selectionColor: Appearance.colors.colOnSurface

    readonly property real leftPad: 22
    readonly property real bottomPad: 18
    readonly property real maxMinutes: root.maximumMinutes()
    property int selectedIndex: -1

    function maximumMinutes() {
        let maximum = 1
        for (let dow = 0; dow < 7; dow++) {
            for (let hour = 0; hour < 24; hour++)
                maximum = Math.max(maximum, Number(root.values[dow]?.[hour]) || 0)
        }
        return maximum
    }

    activeFocusOnTab: true
    implicitHeight: readout.implicitHeight + 4 + root.chartHeight + root.bottomPad + 24
    Accessible.name: readout.text

    function valueAt(index) {
        if (index < 0 || index >= 168)
            return 0
        const dow = Math.floor(index / 24)
        const hour = index % 24
        return Number(root.values[dow]?.[hour]) || 0
    }

    function cellColor(value) {
        const minutes = Math.max(0, Number(value) || 0)
        if (minutes <= 0)
            return root.surfaceColor
        const ratio = minutes / root.maxMinutes
        const alpha = ratio <= 0.25 ? 0.28 : ratio <= 0.5 ? 0.48 : ratio <= 0.75 ? 0.72 : 1
        const color = root.primaryColor
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function indexAt(x, y) {
        const plotWidth = canvas.width - root.leftPad
        if (x < root.leftPad || x >= canvas.width || y < 0 || y >= root.chartHeight)
            return -1
        const hour = Math.min(23, Math.floor((x - root.leftPad) / (plotWidth / 24)))
        const dow = Math.min(6, Math.floor(y / (root.chartHeight / 7)))
        return dow * 24 + hour
    }

    function moveSelection(delta) {
        const start = root.selectedIndex < 0 ? 0 : root.selectedIndex
        root.selectedIndex = Math.max(0, Math.min(167, start + delta))
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) root.moveSelection(-1)
        else if (event.key === Qt.Key_Right) root.moveSelection(1)
        else if (event.key === Qt.Key_Up) root.moveSelection(-24)
        else if (event.key === Qt.Key_Down) root.moveSelection(24)
        else return
        event.accepted = true
    }

    StyledText {
        id: readout
        anchors.left: parent.left
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: {
            if (root.selectedIndex < 0)
                return root.defaultLabel
            const dow = Math.floor(root.selectedIndex / 24)
            const hour = root.selectedIndex % 24
            return root.valueLabel(dow, hour, root.valueAt(root.selectedIndex))
        }
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
            const plotWidth = width - root.leftPad
            const cellWidth = plotWidth / 24
            const cellHeight = height / 7

            for (let dow = 0; dow < 7; dow++) {
                for (let hour = 0; hour < 24; hour++) {
                    const x = root.leftPad + hour * cellWidth + 1
                    const y = dow * cellHeight + 1
                    ctx.fillStyle = root.cellColor(root.values[dow]?.[hour] ?? 0)
                    ctx.fillRect(x, y, Math.max(1, cellWidth - 2), Math.max(1, cellHeight - 2))
                }
            }

            if (root.selectedIndex >= 0) {
                const dow = Math.floor(root.selectedIndex / 24)
                const hour = root.selectedIndex % 24
                ctx.strokeStyle = root.selectionColor
                ctx.lineWidth = 1.5
                ctx.strokeRect(root.leftPad + hour * cellWidth + 0.75,
                               dow * cellHeight + 0.75,
                               Math.max(1, cellWidth - 1.5), Math.max(1, cellHeight - 1.5))
            }
        }

        Connections {
            target: root
            function onValuesChanged() { canvas.requestPaint() }
            function onSelectedIndexChanged() { canvas.requestPaint() }
            function onMaxMinutesChanged() { canvas.requestPaint() }
            function onPrimaryColorChanged() { canvas.requestPaint() }
            function onSurfaceColorChanged() { canvas.requestPaint() }
            function onSelectionColorChanged() { canvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onAvailableChanged: if (available) requestPaint()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: mouse => root.selectedIndex = root.indexAt(mouse.x, mouse.y)
            onExited: if (!root.activeFocus) root.selectedIndex = -1
            onClicked: root.forceActiveFocus()
        }
    }

    Repeater {
        model: 7
        delegate: StyledText {
            required property int index
            anchors.left: parent.left
            y: canvas.y + index * (root.chartHeight / 7)
               + (root.chartHeight / 7 - implicitHeight) / 2
            width: root.leftPad - 3
            horizontalAlignment: Text.AlignRight
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: root.dayLabels[index] ?? ""
        }
    }

    Item {
        id: hourLabels
        anchors.top: canvas.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.bottomPad

        Repeater {
            model: [{ hour: 0, text: "0" }, { hour: 6, text: "6" },
                    { hour: 12, text: "12" }, { hour: 18, text: "18" },
                    { hour: 23, text: "23" }]
            delegate: StyledText {
                required property var modelData
                readonly property real plotWidth: hourLabels.width - root.leftPad
                x: Math.max(root.leftPad, Math.min(hourLabels.width - width,
                    root.leftPad + (modelData.hour + 0.5) * (plotWidth / 24) - width / 2))
                anchors.top: parent.top
                anchors.topMargin: 2
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: modelData.text
            }
        }
    }

    Row {
        anchors.top: hourLabels.bottom
        anchors.left: parent.left
        spacing: 8

        Repeater {
            model: [0.2, 0.45, 0.7, 1]
            delegate: Row {
                required property real modelData
                spacing: 3
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 2
                    color: root.cellColor(root.maxMinutes * modelData)
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    text: Math.round(root.maxMinutes * modelData) + "m"
                }
            }
        }
    }
}
