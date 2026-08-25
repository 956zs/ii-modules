import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.battery_trend

/*
 * Bar slot entry — but NOT a bar widget by default. The stock bar already
 * has a battery gauge, so this module claims zero bar space out of the box
 * (showBar defaults to false). Sampling, persistence, the detail panel, and
 * the IPC surface all live in the window-slot entry (main.qml), which the
 * module host instantiates exactly once; this per-monitor instance is a
 * pure reader that re-derives its views from the watched config file.
 *
 * Opting into showBar renders a sparkline-only pill (percentage text is a
 * further opt-in — the stock widget already shows the number) with the
 * hover popup; clicking asks the window-slot owner to open the panel over
 * IPC, the same path the stock indicator and the sidebar tile use.
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true
    visible: cfg.options.showBar === true

    MouseArea {
        id: root

        implicitWidth: content.implicitWidth + root.hPadding * 2
        implicitHeight: root.barVertical ? content.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.LeftButton
        onPressed: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "--any-display",
                                            "call", "battery_trend", "toggle"])

        readonly property bool barVertical: barGroup.vertical

        readonly property int hPadding: root.barVertical ? 2 : 8

        // Sparkline needs ≥2 samples; until then (first minutes of a fresh
        // install) the percentage stands in so the pill is never blank.
        readonly property bool sparkReady: logic.available && logic.spark.length >= 2

        ConfigLoader {
            id: cfg
            owner: false
        }

        BatteryLogic {
            id: logic
            store: cfg.options
            storeReady: cfg.ready
            sampling: false
            intervalSec: {
                const v = cfg.options.samplingIntervalSec
                return v >= 15 && v <= 600 ? v : 60
            }
            keepHourly: cfg.options.keepHourly === true
            keepDaily: cfg.options.keepDaily === true
            keepSessions: cfg.options.keepSessions === true
            batteryName: cfg.options.batteryName !== "" ? cfg.options.batteryName : "auto"
            fastPoll: popup.active === true
        }

        // Reserved width so the pill doesn't jitter as digits change.
        TextMetrics {
            id: pctMetrics
            text: "100%"
            font.family: Appearance.font.family.main
            font.pixelSize: root.barVertical ? Appearance.font.pixelSize.smaller
                                             : Appearance.font.pixelSize.small
        }

        GridLayout {
            id: content
            anchors.centerIn: parent
            // Vertical bar: 45px pill — percentage above a short sparkline.
            columns: root.barVertical ? 1 : 2
            columnSpacing: 4
            rowSpacing: 1

            StyledText {
                // Stock BatteryIndicator already shows the number — opt-in
                // only, except as a bootstrap fallback for an empty sparkline.
                visible: cfg.options.showPercent === true || !root.sparkReady
                Layout.alignment: Qt.AlignCenter
                Layout.preferredWidth: Math.max(pctMetrics.width, implicitWidth)
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: pctMetrics.font.pixelSize
                // Charging = accent; low on battery = error; otherwise neutral
                // ink (status colours reserved for status).
                color: logic.charging ? Appearance.colors.colPrimary
                     : (logic.chargeClass === 0
                        && logic.pct <= (Config.options.battery?.low ?? 20))
                       ? Appearance.colors.colError
                       : Appearance.colors.colOnLayer1
                text: logic.available ? `${Math.round(logic.pct)}%` : "—"
            }

            TrendGraph {
                visible: root.sparkReady
                Layout.alignment: Qt.AlignCenter
                // A little wider when it is the pill's only content.
                Layout.preferredWidth: root.barVertical ? 30
                    : cfg.options.showPercent === true ? 34 : 44
                Layout.preferredHeight: root.barVertical ? 12 : Math.round(Appearance.sizes.baseBarHeight * 0.42)
                samples: logic.spark
                windowSec: logic.sparkSec
                gapSec: logic.gapSec
                lineColor: Appearance.colors.colOnLayer1
                chargeColor: Appearance.colors.colPrimary
            }
        }

        BatteryPopup {
            id: popup
            hoverTarget: root
            logic: logic
        }
    }
}
