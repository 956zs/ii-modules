import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services

/*
 * Hover popup: the at-a-glance numbers. StyledPopup is a tooltip (it lives
 * exactly as long as the hover), so it takes no clicks — the detail panel
 * opens from a click on the bar widget itself.
 *
 * StyledPopup's default property is a single Item; everything, including
 * non-visual helpers, must live inside it.
 */
StyledPopup {
    id: root
    required property var logic

    function batteryIcon() {
        if (root.logic.charging)
            return "battery_charging_full"
        const p = root.logic.pct
        if (p >= 95) return "battery_full"
        const bars = Math.max(0, Math.min(6, Math.round(p / 100 * 7 - 0.5)))
        return `battery_${bars}_bar`
    }

    function stateLabel() {
        if (!root.logic.available) return Translation.tr("No battery")
        if (root.logic.charging) return Translation.tr("Charging")
        if (root.logic.chargeClass === 0) return Translation.tr("On battery")
        return Translation.tr("Full · on AC")
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        Row {
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 0
                font.weight: Font.DemiBold
                text: root.batteryIcon()
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
                animateChange: true
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: `${Math.round(root.logic.pct)}% · ${root.stateLabel()}`
                font {
                    weight: Font.DemiBold
                    pixelSize: Appearance.font.pixelSize.normal
                }
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: root.logic.charging ? "bolt" : "power_settings_new"
                label: Translation.tr("Power draw:")
                value: root.logic.smoothW > 0.05 || root.logic.upowerW !== 0
                       ? root.logic.fmtW(root.logic.smoothW > 0.05 ? root.logic.smoothW
                                                                   : Math.abs(root.logic.upowerW))
                       : "—"
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "schedule"
                label: root.logic.charging ? Translation.tr("Time to full:")
                                           : Translation.tr("Time left:")
                value: root.logic.estSec > 0 ? root.logic.fmtDur(root.logic.estSec)
                     : root.logic.chargeClass === 2 ? "—"
                     : Translation.tr("measuring…")
            }
            StyledPopupValueRow {
                visible: root.logic.upowerSec > 0 && root.logic.estSec > 0
                Layout.fillWidth: true
                icon: "compare_arrows"
                label: Translation.tr("UPower says:")
                value: root.logic.fmtDur(root.logic.upowerSec)
            }
            StyledPopupValueRow {
                visible: root.logic.healthPct > 0
                Layout.fillWidth: true
                icon: "cardiology"
                label: Translation.tr("Health:")
                value: `${root.logic.healthPct.toFixed(1)}%`
                       + (root.logic.cycles > 0 ? ` · ${root.logic.cycles} ${Translation.tr("cycles")}` : "")
            }
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "trending_down"
                label: Translation.tr("Today used:")
                value: root.logic.stats.today !== undefined && root.logic.stats.today.dis > 0
                       ? `${root.logic.stats.today.dis.toFixed(0)}% · ${root.logic.stats.today.rate.toFixed(1)}%/h`
                       : "—"
            }
            StyledPopupValueRow {
                visible: (root.logic.stats.today?.chgH ?? 0) > 0.05
                Layout.fillWidth: true
                icon: "battery_charging_60"
                label: Translation.tr("Today charged:")
                value: root.logic.fmtDur((root.logic.stats.today?.chgH ?? 0) * 3600)
            }
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Click for detailed trends")
        }
    }
}
