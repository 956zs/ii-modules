import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import qs.mod.network_traffic

/*
 * Bar slot entry (Item root). Self-contained: own BarGroup pill, own logic
 * instance, own config file, hover popup.
 *
 * The layout is responsive, and it has to be. The bar's right section is a
 * right-to-left RowLayout anchored to the middle section's right edge, so
 * anything wider than the leftover space spills *leftwards* and paints on top
 * of the stock widgets instead of being clipped. The middle section reserves
 * barCenterSideModuleWidth (360px per side with bar.verbose on) regardless of
 * screen size, which leaves roughly 65px for this module on a 1920px panel.
 *
 * So: stack the two directions on narrow screens, keep the roomier single-line
 * form on wide ones. Compact metrics are derived from the bar height rather
 * than hardcoded, so the content cannot outgrow the pill at any bar height.
 */
BarGroup {
    id: barGroup

    MouseArea {
        id: root

        implicitWidth: content.implicitWidth + root.hPadding * 2
        implicitHeight: Appearance.sizes.baseBarHeight
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Left-click cycles the popup's totals period, right-click expands the
        // per-app ranking — the popup itself is a hover tooltip and can't take
        // clicks.
        property bool appsExpanded: false
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                const order = ["boot", "today", "month"]
                const i = order.indexOf(cfg.options.statsPeriod)
                cfg.options.statsPeriod = order[(i + 1) % order.length]
            } else if (event.button === Qt.RightButton) {
                root.appsExpanded = !root.appsExpanded
            }
        }

        ConfigLoader { id: cfg }

        readonly property real screenWidth: barGroup.QsWindow.window?.screen?.width ?? 0

        // Config values are coerced, never trusted raw: a file written by an
        // older version has no entry for these keys and the adapter hands back
        // the type zero value rather than the declared default.
        readonly property string displayMode: {
            const mode = cfg.options.displayMode;
            return (mode === "stacked" || mode === "horizontal") ? mode : "auto";
        }
        readonly property int autoStackMaxWidth: cfg.options.autoStackMaxWidth > 0 ? cfg.options.autoStackMaxWidth : 1920

        readonly property bool stacked: {
            if (root.displayMode === "stacked")
                return true;
            if (root.displayMode === "horizontal")
                return false;
            // "auto": stack once the screen is too narrow to afford the wide form.
            // Width 0 means the window isn't attached yet; don't thrash the layout.
            return root.screenWidth > 0 && root.screenWidth <= root.autoStackMaxWidth;
        }
        readonly property bool showIcons: !root.stacked || cfg.options.stackedShowIcons === true

        // BarGroup insets its pill 4px top and bottom, so the visible box is
        // baseBarHeight - 8. Two stacked rows plus ~3px of breathing room at
        // each edge have to fit inside that.
        readonly property real pillHeight: Appearance.sizes.baseBarHeight - 8
        readonly property int rowHeight: Math.max(10, Math.floor((root.pillHeight - 6) / 2))
        readonly property int textSize: root.stacked ? Math.max(9, Math.min(Appearance.font.pixelSize.small, root.rowHeight - 2)) : Appearance.font.pixelSize.small
        readonly property int iconSize: root.stacked ? Math.max(8, root.textSize - 1) : Appearance.font.pixelSize.normal
        readonly property int hPadding: root.stacked ? 4 : 10

        // Values follow the Material You scheme (regenerated from the
        // wallpaper): download primary, upload tertiary — same coding as the
        // popup's two graphs.
        readonly property color downColor: Appearance.colors.colPrimary
        readonly property color upColor: Appearance.colors.colTertiary
        // Breathing arrows above this rate ("high traffic").
        readonly property real breatheThreshold: 1024 * 1024 // 1 MiB/s

        TrafficLogic {
            id: logic
            updateInterval: cfg.options.updateInterval
            excludeRegex: cfg.options.excludeRegex
            store: cfg.options
            storeReady: cfg.ready
        }

        TextMetrics {
            id: speedTextMetrics
            // Reserved width, so the pill doesn't jitter on every sample. The
            // formatter tops out at 4 glyphs in practice ("2.0M", "203K"); the
            // Math.max below still lets a rare 5-glyph value through uncropped.
            text: root.stacked ? "888M" : "888.8M"
            font.family: Appearance.font.family.main
            font.pixelSize: root.textSize
        }

        // Direction arrow that "breathes" while its rate is high. Dim when the
        // direction is quiet, like before.
        component BreathingArrow: MaterialSymbol {
            id: arrow
            property real speed: 0
            fill: 0
            iconSize: root.iconSize
            color: speed >= 1024 ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
            Layout.alignment: Qt.AlignVCenter

            SequentialAnimation {
                running: arrow.visible && arrow.speed >= root.breatheThreshold
                loops: Animation.Infinite
                onStopped: arrow.opacity = 1
                NumberAnimation { target: arrow; property: "opacity"; to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { target: arrow; property: "opacity"; to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }

        // One self-contained row per direction. `columns` flips them between
        // stacked (1) and side by side (2).
        //
        // Deliberately NOT one shared 4-cell grid: GridLayout drops invisible
        // items instead of reserving their cell, so hiding the arrows made the
        // following value shift up into the icon column and knocked the two
        // rows out of alignment.
        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: root.stacked ? 1 : 2
            columnSpacing: 8
            rowSpacing: 0

            RowLayout {
                spacing: 2
                Layout.fillWidth: true
                Layout.preferredHeight: root.stacked ? root.rowHeight : implicitHeight

                BreathingArrow {
                    visible: root.showIcons
                    text: "arrow_downward"
                    speed: logic.downSpeed
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.max(speedTextMetrics.width, implicitWidth)
                    horizontalAlignment: root.stacked ? Text.AlignRight : Text.AlignHCenter
                    font.pixelSize: root.textSize
                    color: root.downColor
                    text: logic.format(logic.downSpeed, false)
                }
            }

            RowLayout {
                spacing: 2
                Layout.fillWidth: true
                Layout.preferredHeight: root.stacked ? root.rowHeight : implicitHeight

                BreathingArrow {
                    visible: root.showIcons
                    text: "arrow_upward"
                    speed: logic.upSpeed
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Math.max(speedTextMetrics.width, implicitWidth)
                    horizontalAlignment: root.stacked ? Text.AlignRight : Text.AlignHCenter
                    font.pixelSize: root.textSize
                    color: root.upColor
                    text: logic.format(logic.upSpeed, false)
                }
            }
        }

        TrafficPopup {
            hoverTarget: root
            logic: logic
            statsPeriod: cfg.options.statsPeriod === "today" || cfg.options.statsPeriod === "month"
                         ? cfg.options.statsPeriod : "boot"
            appsExpanded: root.appsExpanded
            appUpdateInterval: cfg.options.updateInterval
        }
    }
}
