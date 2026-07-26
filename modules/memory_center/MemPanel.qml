import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.memory_center

/*
 * Detail panel content: composition bar + legend, swap bar, treemap-style
 * process blocks, and the two privileged cleanup actions.
 *
 * Block view: one or two rows of proportional rounded blocks. Row heights
 * scale with each row's share of the sampled total and block widths with
 * each item's share of its row — so area stays proportional to RSS across
 * the whole set (a flow-treemap, readable beats fancy). The tail beyond
 * the configured count folds into "Other" instead of more rectangles.
 *
 * Kill affordance: clicking one of the user's own blocks arms it (error
 * container colour), a second click sends SIGTERM. No dialogs; arming
 * decays after a few seconds.
 */
ColumnLayout {
    id: panel
    required property var mem
    required property var procs

    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 10

    property int armedPid: -1
    property string status: ""
    property bool statusError: false

    readonly property bool swapTrimOk: mem.swapUsedKb > 0 && mem.memAvailable > mem.swapUsedKb
    readonly property string swapTrimReason:
        mem.swapTotal <= 0 ? Translation.tr("No swap configured")
        : mem.swapUsedKb <= 0 ? Translation.tr("Swap is empty — nothing to compact")
        : mem.memAvailable <= mem.swapUsedKb ? Translation.tr("Not enough available RAM to unload swap safely")
        : ""

    // Two-row flow-treemap model over the TOP processes: [{frac, total, items}].
    // The "Other" tail is a labeled summary strip below, not a block — its
    // mass regularly dwarfs any single process, and letting it into the area
    // layout squeezes the whole top set into slivers (readable beats fancy).
    readonly property var blockRows: {
        procs.revision
        const items = []
        for (const p of procs.topProcs)
            items.push({ pid: p.pid, name: p.name, user: p.user, rss: p.rss, own: p.own })
        let total = 0
        for (const it of items)
            total += it.rss
        if (total <= 0)
            return []
        if (items.length <= 4)
            return [{ frac: 1, total, items }]
        // Greedy split at half the mass; RSS-descending input keeps row 1 short.
        let acc = 0
        let split = items.length - 1
        for (let i = 0; i < items.length; i++) {
            acc += items[i].rss
            if (acc >= total / 2) {
                split = i + 1
                break
            }
        }
        split = Math.max(1, Math.min(split, items.length - 1))
        const r1 = items.slice(0, split)
        let s1 = 0
        for (const it of r1)
            s1 += it.rss
        return [
            { frac: s1 / total, total: s1, items: r1 },
            { frac: 1 - s1 / total, total: total - s1, items: items.slice(split) }
        ]
    }

    function requestKill(pid, name) {
        if (killProc.running)
            return
        killProc.targetName = name
        killProc.command = ["kill", "-15", String(pid)]
        killProc.running = true
        panel.status = Translation.tr("Sent SIGTERM to %1").arg(name)
        panel.statusError = false
    }

    // --- non-visual helpers (must live inside the visual root) -----------

    Actions {
        id: actions
        mem: panel.mem
    }

    Connections {
        target: actions
        function onPhaseChanged() {
            if (actions.phase === "running") {
                panel.status = Translation.tr("Waiting for authentication…")
                panel.statusError = false
            } else if (actions.phase === "done") {
                panel.status = actions.lastAction === "swap"
                    ? Translation.tr("Moved %1 out of swap").arg(panel.mem.fmt(actions.freedKb))
                    : Translation.tr("Freed %1 of cache").arg(panel.mem.fmt(actions.freedKb))
                panel.statusError = false
            } else if (actions.phase === "error") {
                panel.status = actions.errorText
                panel.statusError = true
            } else {
                panel.status = ""
                panel.statusError = false
            }
        }
    }

    Process {
        id: killProc
        property string targetName: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                panel.status = Translation.tr("Could not signal %1").arg(killProc.targetName)
                panel.statusError = true
            }
            refreshTimer.start()
        }
    }

    Timer {
        id: refreshTimer
        interval: 1000
        onTriggered: {
            panel.procs.pollNow()
            panel.mem.resample()
        }
    }

    Timer {
        id: disarmTimer
        interval: 3500
        onTriggered: panel.armedPid = -1
    }

    // --- header -----------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        MaterialSymbol {
            fill: 0
            font.weight: Font.DemiBold
            text: "memory"
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            text: Translation.tr("Memory")
            font.weight: Font.DemiBold
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: `${panel.mem.fmt(panel.mem.usedKb)} / ${panel.mem.fmt(panel.mem.memTotal)}  ·  ${Math.round(panel.mem.usedFrac * 100)}%`
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    CompositionBar {
        Layout.fillWidth: true
        implicitHeight: 24
        segments: [
            { value: panel.mem.usedKb, color: Appearance.colors.colPrimary },
            { value: panel.mem.reclaimKb, color: Appearance.colors.colSecondaryContainer },
            { value: panel.mem.freeKb, color: Appearance.colors.colSurfaceContainerHighest }
        ]
    }

    Flow {
        Layout.fillWidth: true
        spacing: 14

        component LegendChip: Row {
            property color dotColor
            property string label
            property string value
            spacing: 5

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: parent.dotColor
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.value
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
        }

        LegendChip {
            dotColor: Appearance.colors.colPrimary
            label: Translation.tr("Apps")
            value: panel.mem.fmt(panel.mem.usedKb)
        }
        LegendChip {
            dotColor: Appearance.colors.colSecondaryContainer
            label: Translation.tr("Cache & buffers")
            value: panel.mem.fmt(panel.mem.reclaimKb)
        }
        LegendChip {
            dotColor: Appearance.colors.colSurfaceContainerHighest
            label: Translation.tr("Free")
            value: panel.mem.fmt(panel.mem.freeKb)
        }
    }

    // --- swap -------------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2

        StyledText {
            text: "Swap"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSurfaceVariant
        }
        Item { Layout.fillWidth: true }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
            text: panel.mem.swapTotal > 0
                  ? `${panel.mem.fmt(panel.mem.swapUsedKb)} / ${panel.mem.fmt(panel.mem.swapTotal)}`
                  : Translation.tr("none")
        }
    }

    CompositionBar {
        Layout.fillWidth: true
        implicitHeight: 8
        visible: panel.mem.swapTotal > 0
        segments: [
            { value: panel.mem.swapUsedKb, color: Appearance.colors.colTertiary },
            { value: panel.mem.swapFree, color: Appearance.colors.colSurfaceContainerHighest }
        ]
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    // --- process blocks ---------------------------------------------------

    StyledText {
        text: Translation.tr("Top processes by memory")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnSurfaceVariant
    }

    StyledText {
        visible: panel.blockRows.length === 0
        Layout.fillWidth: true
        text: Translation.tr("Sampling processes…")
        color: Appearance.colors.colOnLayer1Inactive
    }

    Column {
        id: blockArea
        Layout.fillWidth: true
        visible: panel.blockRows.length > 0
        spacing: 2
        readonly property real areaHeight: 92

        Repeater {
            model: panel.blockRows.length

            Item {
                id: rowItem
                required property int index
                readonly property var rowData: panel.blockRows[index] ?? { frac: 0, total: 1, items: [] }
                width: blockArea.width
                height: Math.max(26, blockArea.areaHeight * rowData.frac)

                Row {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                        model: rowItem.rowData.items

                        Rectangle {
                            id: block
                            required property var modelData
                            readonly property bool armed: modelData.own && panel.armedPid === modelData.pid

                            width: Math.max(6, (rowItem.width - 2 * (rowItem.rowData.items.length - 1)) * modelData.rss / rowItem.rowData.total)
                            height: rowItem.height
                            radius: 6
                            color: armed ? Appearance.m3colors.m3errorContainer
                                 : blockMa.containsMouse ? Appearance.colors.colSecondaryContainerHover
                                 : Appearance.colors.colSecondaryContainer

                            readonly property color ink: armed ? Appearance.m3colors.m3onErrorContainer
                                                        : Appearance.colors.colOnSecondaryContainer

                            Column {
                                anchors.centerIn: parent
                                visible: block.width >= 34
                                spacing: 0

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(implicitWidth, block.width - 10)
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: block.ink
                                    text: block.armed ? Translation.tr("End?") : block.modelData.name
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: block.width >= 52 && block.height >= 36
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: block.ink
                                    opacity: 0.8
                                    text: panel.mem.fmtShort(block.modelData.rss)
                                }
                            }

                            MouseArea {
                                id: blockMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: block.modelData.own ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (!block.modelData.own)
                                        return
                                    if (panel.armedPid === block.modelData.pid) {
                                        panel.requestKill(block.modelData.pid, block.modelData.name)
                                        panel.armedPid = -1
                                    } else {
                                        panel.armedPid = block.modelData.pid
                                        disarmTimer.restart()
                                    }
                                }

                                StyledToolTip {
                                    extraVisibleCondition: blockMa.containsMouse
                                    text: block.armed
                                          ? Translation.tr("Click again to send SIGTERM")
                                          : `${block.modelData.name} · ${panel.mem.fmtShort(block.modelData.rss)} · PID ${block.modelData.pid}`
                                            + (block.modelData.own ? "" : ` · ${block.modelData.user}`)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // "Other" tail: a labeled summary strip, deliberately outside the area
    // encoding (see blockRows).
    Rectangle {
        Layout.fillWidth: true
        visible: procs.otherKb > 0
        implicitHeight: 22
        radius: 6
        color: Appearance.colors.colSurfaceContainerHighest

        StyledText {
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnSurfaceVariant
            text: `${Translation.tr("Other")} · ${panel.mem.fmtShort(procs.otherKb)} · ${Translation.tr("%1 processes").arg(procs.otherCount)}`
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer1Inactive
        text: Translation.tr("Blocks are sized by resident memory (RSS). Click one of your own processes twice to end it (SIGTERM).")
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    // --- cleanup ----------------------------------------------------------

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        component ActionButton: RippleButton {
            id: btn
            // `icon` is Controls Button's FINAL grouped property.
            property string iconName
            property string hint: ""
            Layout.fillWidth: true
            implicitHeight: 34
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            contentItem: RowLayout {
                spacing: 5
                Item { Layout.fillWidth: true }
                MaterialSymbol {
                    fill: 0
                    text: btn.iconName
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    text: btn.buttonText
                    color: Appearance.colors.colOnSecondaryContainer
                }
                Item { Layout.fillWidth: true }
            }

            // Hover probe that still works while the button is disabled, so
            // the tooltip can explain WHY it is disabled. NoButton = clicks
            // pass through to the button itself.
            MouseArea {
                id: hoverProbe
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                StyledToolTip {
                    extraVisibleCondition: btn.hint !== "" && hoverProbe.containsMouse
                    text: btn.hint
                }
            }
        }

        ActionButton {
            iconName: "move_up"
            buttonText: Translation.tr("Compact swap")
            enabled: panel.swapTrimOk && actions.phase !== "running"
            hint: panel.swapTrimReason
            onClicked: actions.trimSwap()
        }

        ActionButton {
            iconName: "mop"
            buttonText: Translation.tr("Drop caches")
            enabled: actions.phase !== "running"
            onClicked: actions.dropCaches()
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer1Inactive
        text: Translation.tr("Caches are performance's friend — dropping them is mainly for measurement; the kernel reclaims cache by itself when memory is needed.")
    }

    StyledText {
        visible: panel.status !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: panel.statusError ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        text: panel.status
    }
}
