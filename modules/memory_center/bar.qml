import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.memory_center

/*
 * Bar slot entry. Compact RAM gauge: memory glyph + used percentage, its
 * colour drifting from the normal text tone toward the error tone as
 * available memory shrinks past the warning threshold — state reads even
 * with the percentage hidden.
 *
 * Hover: composition popup. Click (or `qs -c ii ipc --any-display call
 * memory_center toggle`): the detail panel. The panel loads lazily on
 * first open and then stays loaded, so cleanup Processes in flight
 * survive the panel being closed.
 */
BarGroup {
    id: barGroup
    vertical: Config.options.bar.vertical === true

    MouseArea {
        id: root

        implicitWidth: content.implicitWidth + root.hPadding * 2
        implicitHeight: root.barVertical ? content.implicitHeight + 8 : Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        readonly property bool barVertical: barGroup.vertical
        readonly property int hPadding: root.barVertical ? 2 : 8
        readonly property int textSize: root.barVertical ? Appearance.font.pixelSize.smaller
                                                         : Appearance.font.pixelSize.small

        ConfigLoader { id: cfg; owner: true }

        // Ids deliberately differ from the mem/procs property names they are
        // bound to below: inside the LazyLoader's component scope a binding
        // like `mem: mem` resolves to the property itself (undefined), not
        // the outer id.
        MemInfo {
            id: memInfo
            updateInterval: cfg.options.meminfoInterval >= 500 ? cfg.options.meminfoInterval : 2000
        }

        // Samples only while the panel is open; spawns nothing otherwise.
        ProcTop {
            id: procTop
            active: panelLoader.active && (panelLoader.item?.visible ?? false)
            updateInterval: cfg.options.procInterval >= 1000 ? cfg.options.procInterval : 4000
            topCount: cfg.options.blockCount > 0 ? cfg.options.blockCount : 12
        }

        // Below the warning threshold: normal text tone. Past it, drift
        // linearly toward the error tone (status colour with the glyph and
        // the number right there — never colour alone).
        readonly property real warnFrac: Math.min(0.96, Math.max(0.5, (cfg.options.warnPercent > 0 ? cfg.options.warnPercent : 85) / 100))
        readonly property real pressure: Math.max(0, Math.min(1, (memInfo.usedFrac - root.warnFrac) / (0.98 - root.warnFrac)))
        readonly property color gaugeColor: ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colOnLayer1, root.pressure)

        function togglePanel() {
            if (!panelLoader.active) {
                panelLoader.active = true // PanelShell starts visible
                return
            }
            const panel = panelLoader.item
            if (!panel)
                return
            if (panel.visible) {
                panel.visible = false
            } else if (Date.now() - panel.lastCloseTime > 300) {
                // A click on the bar widget first collapses the panel via its
                // focus grab, then lands here — don't instantly reopen.
                panel.visible = true
            }
        }

        onPressed: root.togglePanel()

        // Testability hook — IpcHandler is non-visual, so it lives inside
        // the visual root: `qs -c ii ipc --any-display call memory_center toggle`
        IpcHandler {
            target: "memory_center"

            function toggle(): void {
                root.togglePanel()
            }
        }

        TextMetrics {
            id: pctMetrics
            text: "88%"
            font.family: Appearance.font.family.main
            font.pixelSize: root.textSize
        }

        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: root.barVertical ? 1 : 2
            columnSpacing: 3
            rowSpacing: 0

            MaterialSymbol {
                Layout.alignment: root.barVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                fill: 0
                text: "memory"
                iconSize: root.barVertical ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.large
                color: root.gaugeColor
            }

            StyledText {
                visible: cfg.options.showBarPercent !== false
                Layout.alignment: root.barVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                Layout.preferredWidth: Math.max(pctMetrics.width, implicitWidth)
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: root.textSize
                color: root.gaugeColor
                // Vertical pill is ~27px wide: drop the % sign, keep the number.
                text: root.barVertical ? String(Math.round(memInfo.usedFrac * 100))
                                       : Math.round(memInfo.usedFrac * 100) + "%"
            }
        }

        MemPopup {
            hoverTarget: root
            mem: memInfo
        }

        LazyLoader {
            id: panelLoader
            active: false

            component: PanelShell {
                panelWidth: 440

                MemPanel {
                    mem: memInfo
                    procs: procTop
                }
            }
        }
    }
}
