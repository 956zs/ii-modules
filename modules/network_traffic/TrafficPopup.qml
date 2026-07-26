import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.services
import qs.mod.network_traffic

/*
 * Hover popup. StyledPopup is a tooltip (it lives exactly as long as the
 * hover), so all interaction happens on the bar widget itself:
 *   left-click  — cycle the totals period  Boot → Today → This month
 *   right-click — expand/collapse the per-app ranking
 *
 * The bar entry owns that state and mirrors it in via statsPeriod /
 * appsExpanded.
 */
StyledPopup {
    id: root
    required property var logic
    required property var appTraffic
    property bool appsEnabled: true
    property string statsPeriod: "boot"
    property bool appsExpanded: false

    readonly property real periodRx: statsPeriod === "today" ? logic.todayRx
                                   : statsPeriod === "month" ? logic.monthRx
                                   : logic.totalRx
    readonly property real periodTx: statsPeriod === "today" ? logic.todayTx
                                   : statsPeriod === "month" ? logic.monthTx
                                   : logic.totalTx
    readonly property string periodLabel: statsPeriod === "today" ? Translation.tr("Today")
                                        : statsPeriod === "month" ? Translation.tr("This month")
                                        : Translation.tr("Boot")

    // Accumulated per-app totals for the selected period. acctRevision is
    // referenced so the binding re-evaluates as accounting rolls in.
    readonly property list<var> appRanking: {
        appTraffic.acctRevision
        return appTraffic.ranking(statsPeriod)
    }
    readonly property var topApp: appRanking.length > 0 ? appRanking[0] : null
    readonly property real topShare: {
        if (!topApp) return 0
        let total = 0
        for (const a of appRanking) total += a.rx + a.tx
        return total > 0 ? (topApp.rx + topApp.tx) / total : 0
    }

    function appName(name) {
        return name === appTraffic.otherKey ? Translation.tr("Other") : name
    }

    // --- latency ---------------------------------------------------------
    // One ping in flight at a time, only while the popup is open. Target
    // "auto" resolves the host's configured DNS once per popup lifetime.

    property string pingHost: "auto"
    property string resolvedDns: ""
    readonly property string pingTarget: pingHost !== "auto" ? pingHost : resolvedDns
    property real pingMs: -1 // -1 pending, -2 timeout/unreachable

    onActiveChanged: {
        pingMs = -1
        if (active && pingHost === "auto" && resolvedDns === "") {
            dnsProc.running = true
        }
    }

    function pickDns(text) {
        // Skip loopback stubs (systemd-resolved) and the tailscale magic
        // resolver; prefer a public address ("the host's public DNS") over
        // the router.
        const seen = []
        for (const tok of text.split(/\s+/)) {
            if (!/^[0-9a-fA-F.:]+$/.test(tok) || !/[.:]/.test(tok)) continue
            if (tok.startsWith("127.") || tok === "::1") continue
            if (tok === "100.100.100.100" || tok.toLowerCase().startsWith("fd7a:115c:a1e0")) continue
            if (!seen.includes(tok)) seen.push(tok)
        }
        const isPrivate = a =>
            a.startsWith("192.168.") || a.startsWith("10.") || a.startsWith("169.254.") ||
            /^172\.(1[6-9]|2[0-9]|3[01])\./.test(a) ||
            a.toLowerCase().startsWith("fe80") || /^f[cd]/i.test(a)
        return seen.find(a => !isPrivate(a)) ?? seen[0] ?? ""
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        // StyledPopup's default property is a single Item — non-visual
        // helpers must live inside it, not on the popup root.
        Process {
            id: dnsProc
            command: ["sh", "-c", "resolvectl dns 2>/dev/null; grep -h '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}'"]
            stdout: StdioCollector {
                onStreamFinished: root.resolvedDns = root.pickDns(text)
            }
        }

        Timer {
            running: root.active && root.pingTarget !== ""
            interval: 3000
            repeat: true
            triggeredOnStart: true
            onTriggered: if (!pingProc.running) pingProc.running = true
        }

        Process {
            id: pingProc
            command: ["ping", "-n", "-c", "1", "-W", "2", root.pingTarget]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/time=([\d.]+)/)
                    if (m) root.pingMs = parseFloat(m[1])
                }
            }
            onExited: (exitCode, exitStatus) => {
                if (exitCode !== 0) root.pingMs = -2
            }
        }

        // The stock Network service only refreshes on nmcli monitor events —
        // connection changes, not signal drift. Poll its public update() while
        // the popup is open so the header icon tracks live signal strength.
        Timer {
            running: root.active
            interval: 5000
            repeat: true
            triggeredOnStart: true
            onTriggered: Network.update()
        }

        // Stock StyledPopupHeaderRow, unrolled so the icon can animate: the
        // signal-strength glyph slide-fades on change (StyledText's
        // animateChange) instead of hard-swapping.
        Row {
            spacing: 5

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 0
                font.weight: Font.DemiBold
                text: Network.materialSymbol
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSurfaceVariant
                animateChange: true
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Network.networkName
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
                icon: "arrow_downward"
                label: Translation.tr("Download:")
                value: root.logic.format(root.logic.downSpeed, true)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "arrow_upward"
                label: Translation.tr("Upload:")
                value: root.logic.format(root.logic.upSpeed, true)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "network_ping"
                label: Translation.tr("Ping:")
                value: root.pingMs >= 0 ? `${Math.round(root.pingMs)} ms`
                     : root.pingMs === -2 ? Translation.tr("timeout")
                     : root.pingTarget === "" ? "—" : "…"
            }
        }

        ColumnLayout {
            spacing: 4

            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "history"
                label: Translation.tr("Statistics:")
                value: root.periodLabel
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "download"
                label: Translation.tr("Received:")
                value: root.logic.formatTotal(root.periodRx)
            }
            StyledPopupValueRow {
                Layout.fillWidth: true
                icon: "upload"
                label: Translation.tr("Sent:")
                value: root.logic.formatTotal(root.periodTx)
            }
        }

        ColumnLayout {
            spacing: 4

            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "arrow_downward"
                    color: Appearance.colors.colPrimary
                    iconSize: Appearance.font.pixelSize.smaller
                }
                BezierGraph {
                    Layout.fillWidth: true
                    implicitWidth: 170
                    implicitHeight: 32
                    values: root.logic.downHistory
                    color: Appearance.colors.colPrimary
                    maxLabel: root.logic.format(Math.max(...root.logic.downHistory, 0), true)
                }
            }
            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "arrow_upward"
                    color: Appearance.colors.colTertiary
                    iconSize: Appearance.font.pixelSize.smaller
                }
                BezierGraph {
                    Layout.fillWidth: true
                    implicitWidth: 170
                    implicitHeight: 32
                    values: root.logic.upHistory
                    color: Appearance.colors.colTertiary
                    maxLabel: root.logic.format(Math.max(...root.logic.upHistory, 0), true)
                }
            }
        }

        // Per-app section: accumulated totals for the selected period. One
        // summary line; right-click on the bar widget expands the top five.
        ColumnLayout {
            visible: root.appsEnabled
            spacing: 4

            RowLayout {
                spacing: 4
                MaterialSymbol {
                    text: "apps"
                    color: Appearance.colors.colOnSurfaceVariant
                    iconSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnSurfaceVariant
                    text: {
                        if (root.appTraffic.source === "none") return Translation.tr("Per-app stats unavailable")
                        if (!root.topApp) {
                            return root.appTraffic.source === "starting"
                                ? Translation.tr("Measuring per-app usage…")
                                : Translation.tr("No data yet")
                        }
                        return `${root.appName(root.topApp.name)}  ${Math.round(root.topShare * 100)}%`
                    }
                }
                StyledText {
                    visible: root.appTraffic.tcpOnly
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1Inactive
                    text: Translation.tr("TCP only")
                }
            }

            Repeater {
                model: root.appsExpanded ? root.appRanking.slice(0, 5) : []
                delegate: RowLayout {
                    required property var modelData
                    spacing: 4
                    Layout.leftMargin: Appearance.font.pixelSize.large + 4

                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 90
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.appName(modelData.name)
                    }
                    MaterialSymbol {
                        text: "arrow_downward"
                        color: Appearance.colors.colPrimary
                        iconSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.logic.formatTotal(modelData.rx)
                    }
                    MaterialSymbol {
                        text: "arrow_upward"
                        color: Appearance.colors.colTertiary
                        iconSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        text: root.logic.formatTotal(modelData.tx)
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1Inactive
            text: Translation.tr("Click: period · Right-click: apps")
        }
    }
}
