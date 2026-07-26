import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.battery_trend

/*
 * Bar slot entry (visual root). Self-contained: own BarGroup pill, own
 * sampling instance, own config file, hover popup, click-to-open detail
 * panel. Deliberately does NOT duplicate the stock BatteryIndicator's icon —
 * this widget's job is the trend: percentage + a 3 h sparkline.
 *
 * Multi-monitor: the bar slot is instantiated once per screen, but the
 * history file must have exactly one writer. The instance on the first
 * screen is elected primary (samples + persists + materialises config
 * defaults); the others run the logic in reader mode, re-deriving their
 * views from the watched config file.
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true

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

        ConfigLoader {
            id: cfg
            owner: root.isPrimary
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
                visible: logic.available && logic.spark.length >= 2
                Layout.alignment: Qt.AlignCenter
                Layout.preferredWidth: root.barVertical ? 30 : 34
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
