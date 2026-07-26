import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.screentime

/*
 * Bar slot entry (Item root): today's total screen time as a compact
 * "6h 23m" pill. Purely a READER — the accountant lives in main.qml's window
 * slot (bar entries are instantiated per bar/monitor and would double-count),
 * so this widget parses the persisted blob and refreshes on every flush
 * (at most one minute stale, which matches the displayed granularity).
 *
 * Hover: popup with today's total, top 5 apps, yesterday comparison.
 * Click: opens the detail panel (same IPC the sidebar tile uses).
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true

    MouseArea {
        id: root

        implicitWidth: root.barVertical ? contentVertical.implicitWidth + 4 : content.implicitWidth + 10 * 2
        implicitHeight: root.barVertical ? contentVertical.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        onPressed: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "--any-display", "call", "screentime", "toggleDetails"])

        readonly property bool barVertical: barGroup.vertical

        ConfigLoader { id: cfg }
        Format { id: fmt }

        // Rolls the displayed day over at midnight even though the blob's
        // day key only changes on the owner's next flush.
        property string todayKey: root.dayKeyOf(new Date())
        function dayKeyOf(d) {
            return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
        }
        Timer {
            interval: 30000
            running: true
            repeat: true
            onTriggered: root.todayKey = root.dayKeyOf(new Date())
        }

        readonly property var hist: {
            if (!cfg.ready || cfg.options.histState === "") return null
            try {
                return JSON.parse(cfg.options.histState)
            } catch (e) {
                return null
            }
        }
        readonly property var todayApps: (root.hist?.day?.k === root.todayKey
                                          && typeof root.hist.day.apps === "object"
                                          && root.hist.day.apps !== null)
                                         ? root.hist.day.apps : ({})
        readonly property real todayTotal: {
            let t = 0
            for (const v of Object.values(root.todayApps)) t += Number(v) || 0
            return t
        }
        readonly property list<var> ranking: Object.entries(root.todayApps)
            .map(([n, s]) => ({ n, s: Number(s) || 0 }))
            .filter(a => a.s >= 60)
            .sort((a, b) => b.s - a.s)
        // -1 = no record for yesterday (don't fake a zero comparison)
        readonly property real yesterdayTotal: {
            const d = new Date()
            d.setDate(d.getDate() - 1)
            const k = root.dayKeyOf(d)
            const rec = (root.hist?.days ?? []).find(x => x?.k === k)
            return rec ? (Number(rec.total) || 0) : -1
        }

        RowLayout {
            id: content
            visible: !root.barVertical
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                text: "timelapse"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: fmt.dur(root.todayTotal)
            }
        }

        // Vertical bar: ~27px content box — icon above a compact value.
        ColumnLayout {
            id: contentVertical
            visible: root.barVertical
            anchors.centerIn: parent
            spacing: 1

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "timelapse"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                text: fmt.durCompact(root.todayTotal)
            }
        }

        ScreentimePopup {
            hoverTarget: root
            todayTotal: root.todayTotal
            ranking: root.ranking
            yesterdayTotal: root.yesterdayTotal
        }
    }
}
