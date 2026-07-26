import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.battery_trend

/*
 * Detail panel: a bar-adjacent floating window (click the bar widget to
 * toggle), closing on click-outside or Esc. Sections: live header, 24 h
 * curve, 30 d daily range, health trend, analysis stats, recent sessions.
 */
PanelWindow {
    id: root
    required property var logic
    property var openerScreen: null
    property real panelWidth: 420

    visible: false
    function toggle() {
        root.visible = !root.visible
    }

    screen: root.openerScreen ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "quickshell:iimp-battery-trend"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Sit under (or beside) the bar near its right/indicator end.
    anchors.top: !Config.options.bar.vertical && !Config.options.bar.bottom
    anchors.bottom: Config.options.bar.bottom || Config.options.bar.vertical
    anchors.left: Config.options.bar.vertical && !Config.options.bar.bottom
    anchors.right: !Config.options.bar.vertical || Config.options.bar.bottom
    margins {
        top: Appearance.sizes.barHeight
        bottom: Config.options.bar.vertical ? 8 : Appearance.sizes.barHeight
        left: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 8
        right: Config.options.bar.vertical ? Appearance.sizes.verticalBarWidth : 8
    }

    implicitWidth: root.panelWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: background.implicitHeight + Appearance.sizes.elevationMargin * 2

    HyprlandFocusGrab {
        active: root.visible
        windows: [root]
        onCleared: root.visible = false
    }

    Item {
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: root.visible = false

        StyledRectangularShadow {
            target: background
        }

        Rectangle {
            id: background
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin
            implicitHeight: column.implicitHeight + 16 * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            component SectionLabel: StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
            }

            component StatTile: ColumnLayout {
                property string label
                property string value
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    text: parent.value
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    text: parent.label
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                }
            }

            ColumnLayout {
                id: column
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 10

                // --- live header -----------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledText {
                        text: `${Math.round(root.logic.pct)}%`
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: root.logic.charging ? Appearance.colors.colPrimary
                                                   : Appearance.colors.colOnSurface
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true

                        StyledText {
                            text: {
                                if (root.logic.charging)
                                    return Translation.tr("Charging · %1").arg(root.logic.fmtW(root.logic.smoothW))
                                if (root.logic.chargeClass === 0)
                                    return Translation.tr("Discharging · %1").arg(root.logic.fmtW(root.logic.smoothW))
                                return Translation.tr("Full · on AC")
                            }
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            visible: root.logic.estSec > 0
                            text: (root.logic.charging ? Translation.tr("Full in %1")
                                                       : Translation.tr("Empty in %1"))
                                  .arg(root.logic.fmtDur(root.logic.estSec))
                                  + (root.logic.upowerSec > 0
                                     ? `  (UPower: ${root.logic.fmtDur(root.logic.upowerSec)})` : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                    }
                }

                // --- 24 h curve ------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    SectionLabel { text: Translation.tr("Last 24 hours") }
                    // Legend: identity is never colour-alone (labels name it).
                    Rectangle { width: 10; height: 3; radius: 1.5; color: Appearance.colors.colPrimary }
                    StyledText {
                        text: Translation.tr("charging")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                    Rectangle { width: 10; height: 3; radius: 1.5; color: Appearance.colors.colOnSurfaceVariant }
                    StyledText {
                        text: Translation.tr("on battery")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                }

                DayChart {
                    Layout.fillWidth: true
                    implicitHeight: 130
                    samples: root.logic.dayCurve
                    gapSec: root.logic.gapSec
                    fmtClock: root.logic.fmtClock
                }

                StyledText {
                    visible: root.logic.dayCurve.length < 2
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                    text: Translation.tr("Collecting data — the curve fills in as the shell runs.")
                }

                // --- 30 d band -------------------------------------------
                SectionLabel { text: Translation.tr("Last 30 days (daily min–max, ⌀ average)") }

                BandChart {
                    Layout.fillWidth: true
                    implicitHeight: 100
                    days: root.logic.bandDays
                    fmtDay: root.logic.fmtDay
                }

                // --- health ----------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    SectionLabel {
                        Layout.fillWidth: true
                        text: Translation.tr("Battery health (% of design capacity)")
                    }
                    StyledText {
                        visible: root.logic.healthPct > 0
                        text: `${root.logic.healthPct.toFixed(1)}%`
                              + (root.logic.cycles > 0 ? ` · ${root.logic.cycles} ${Translation.tr("cycles")}` : "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colError
                    }
                }

                HealthChart {
                    visible: root.logic.healthSeries.length >= 2
                    Layout.fillWidth: true
                    implicitHeight: 90
                    series: root.logic.healthSeries
                    fmtDay: root.logic.fmtDay
                }

                StyledText {
                    visible: root.logic.healthSeries.length < 2
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                    text: Translation.tr("Health trend appears after a few days of snapshots.")
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    visible: root.logic.stats.h30 !== null && root.logic.stats.h30 !== undefined
                             || root.logic.stats.hSpan !== null && root.logic.stats.hSpan !== undefined
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                    wrapMode: Text.WordWrap
                    text: {
                        const st = root.logic.stats
                        let parts = []
                        if (st.h30 !== null && st.h30 !== undefined)
                            parts.push(Translation.tr("30 d: %1 pp").arg(st.h30 > 0 ? `+${st.h30}` : `${st.h30}`))
                        if (st.hSpan !== null && st.hSpan !== undefined)
                            parts.push(Translation.tr("%1 d: %2 pp").arg(st.hSpanDays)
                                       .arg(st.hSpan > 0 ? `+${st.hSpan}` : `${st.hSpan}`))
                        return parts.join(" · ")
                    }
                }

                // --- analysis stats --------------------------------------
                SectionLabel { text: Translation.tr("Usage analysis") }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: 8
                    columnSpacing: 8

                    StatTile {
                        label: Translation.tr("Drain today")
                        value: (root.logic.stats.today?.rate ?? 0) > 0
                               ? `${root.logic.stats.today.rate.toFixed(1)}%/h` : "—"
                    }
                    StatTile {
                        label: Translation.tr("Drain 7 d")
                        value: (root.logic.stats.d7?.rate ?? 0) > 0
                               ? `${root.logic.stats.d7.rate.toFixed(1)}%/h` : "—"
                    }
                    StatTile {
                        label: Translation.tr("Drain 30 d")
                        value: (root.logic.stats.d30?.rate ?? 0) > 0
                               ? `${root.logic.stats.d30.rate.toFixed(1)}%/h` : "—"
                    }
                    StatTile {
                        label: Translation.tr("Cycles 7 d")
                        value: (root.logic.stats.d7?.cycles ?? 0) > 0
                               ? root.logic.stats.d7.cycles.toFixed(2) : "—"
                    }
                    StatTile {
                        label: Translation.tr("Cycles 30 d")
                        value: (root.logic.stats.d30?.cycles ?? 0) > 0
                               ? root.logic.stats.d30.cycles.toFixed(2) : "—"
                    }
                    StatTile {
                        label: Translation.tr("Avg discharge depth")
                        value: (root.logic.stats.dod ?? -1) > 0
                               ? `${root.logic.stats.dod.toFixed(0)}%` : "—"
                    }
                    StatTile {
                        Layout.columnSpan: 3
                        label: Translation.tr("Typical charge window")
                        value: (root.logic.stats.chargeFrom ?? -1) >= 0
                               ? `${root.logic.stats.chargeFrom}% → ${root.logic.stats.chargeTo}%` : "—"
                    }
                }

                // --- sessions --------------------------------------------
                SectionLabel {
                    visible: root.logic.sessionsRecent.length > 0
                    text: Translation.tr("Recent sessions")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Repeater {
                        model: root.logic.sessionsRecent
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6

                            MaterialSymbol {
                                text: modelData[0] === "c" ? "power" : "battery_horiz_075"
                                iconSize: Appearance.font.pixelSize.small
                                color: modelData[0] === "c" ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: `${root.logic.fmtDay(modelData[1])} ${root.logic.fmtClock(modelData[1])}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.logic.fmtDur(modelData[2] - modelData[1])
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                text: `${Math.round(modelData[3])}% → ${Math.round(modelData[4])}%`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }
            }
        }
    }
}
