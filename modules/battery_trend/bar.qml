import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.battery_trend

/*
 * Bar slot entry — but NOT a bar widget by default. The stock bar already
 * has a battery gauge, so this module claims zero bar space out of the box
 * (showBar defaults to false): this root exists to host the sampling
 * instance, the config file, and the detail panel with its IPC surface,
 * and stays invisible (layouts skip invisible items, so no ghost margins).
 * The sidebar tile / `ipc call battery_trend toggle` is the primary entry.
 *
 * Opting into showBar renders a sparkline-only pill (percentage text is a
 * further opt-in — the stock widget already shows the number) with the
 * hover popup and click-to-open panel.
 *
 * Multi-monitor: the bar slot is instantiated once per screen, but the
 * history file must have exactly one writer. The instance on the first
 * screen is elected primary (samples + persists + materialises config
 * defaults + registers the IPC target); the others run the logic in reader
 * mode, re-deriving their views from the watched config file.
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
        onPressed: detailPanel.toggle()

        readonly property bool barVertical: barGroup.vertical
        readonly property int hPadding: root.barVertical ? 2 : 8

        // Primary election: the window attaches to its screen asynchronously,
        // so this settles a moment after creation; ConfigLoader.owner and
        // BatteryLogic.sampling both follow it.
        readonly property bool isPrimary: {
            const scr = Quickshell.screens
            if (scr.length <= 1)
                return true
            const name = barGroup.QsWindow.window?.screen?.name ?? ""
            return name !== "" && name === scr[0].name
        }

        // Sparkline needs ≥2 samples; until then (first minutes of a fresh
        // install) the percentage stands in so the pill is never blank.
        readonly property bool sparkReady: logic.available && logic.spark.length >= 2

        ConfigLoader {
            id: cfg
            owner: root.isPrimary
        }

        // Sidebar tile entry point. Gated to the primary instance: the bar
        // slot exists once per screen and duplicate IpcHandler targets would
        // collide.
        LazyLoader {
            active: root.isPrimary

            IpcHandler {
                target: "battery_trend"

                function toggle(): void {
                    // Opened from the sidebar tile: drop the sidebar first so
                    // the two focus grabs don't fight over who closes whom.
                    GlobalStates.sidebarRightOpen = false
                    detailPanel.toggle()
                }
            }
        }

        BatteryLogic {
            id: logic
            store: cfg.options
            storeReady: cfg.ready
            sampling: root.isPrimary
            intervalSec: {
                const v = cfg.options.samplingIntervalSec
                return v >= 15 && v <= 600 ? v : 60
            }
            keepHourly: cfg.options.keepHourly === true
            keepDaily: cfg.options.keepDaily === true
            keepSessions: cfg.options.keepSessions === true
            batteryName: cfg.options.batteryName !== "" ? cfg.options.batteryName : "auto"
            fastPoll: popup.active === true || detailPanel.visible
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

        DetailPanel {
            id: detailPanel
            logic: logic
            openerScreen: barGroup.QsWindow.window?.screen ?? null
        }
    }
}
