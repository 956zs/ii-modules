import QtQuick
import QtQuick.Layouts
import qs.mod.adaptive_bar
import "Fit.js" as Fit

/*
 * Fit controller for one horizontal bar. The BarContent patch instantiates one
 * per screen, binds the stock section items in, and applies `fold` to the
 * tray and `side` to both centre side groups.
 *
 * Inputs are read after a short settle delay so nested layouts have polished
 * (Revealer animations keep restarting it until they finish). The decision is
 * the pure Fit.settle() over fold-independent inputs, so applying it cannot
 * feed back into the next decision.
 */
Item {
    id: root

    visible: false

    property real barWidth: 0
    property int stockSideWidth: 0
    property Item middle: null
    property Item leftSide: null
    property Item rightSide: null
    property Item rightContent: null
    property Item rightRow: null
    property Item tray: null

    readonly property int sideMax: Math.min(root.stockSideWidth, Fit.clampInt(config.options.centerSideMaxWidth, Fit.SIDE_SETTING_MIN, Fit.SIDE_SETTING_MAX, Fit.SIDE_SETTING_MAX))

    // Applied by the BarContent patch.
    property int fold: 0
    property int side: root.sideMax
    property int overflow: 0

    ConfigLoader {
        id: config
    }

    // Content minimum of the left centre group (stock: Resources + Media).
    // Its implicitWidth is bound to the side width, so read the children.
    readonly property real leftMin: {
        const items = root.leftSide?.items ?? [];
        const entries = [];
        let spacing = 0;
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            spacing = item.parent?.columnSpacing ?? spacing;
            entries.push({
                visible: item.visible,
                fill: item.Layout?.fillWidth ?? false,
                width: item.implicitWidth
            });
        }
        return Fit.groupMinWidth(entries, spacing, root.leftSide?.padding ?? 0, Fit.ELASTIC_MIN);
    }

    readonly property bool trayFoldable: root.tray !== null && root.tray.visible && root.tray.showOverflowMenu

    readonly property var inputs: [root.barWidth, root.sideMax, root.leftMin, root.trayFoldable, root.middle?.width, root.leftSide?.width, root.rightSide?.width, root.rightContent?.implicitWidth, root.rightRow?.implicitWidth, root.tray?.pinnedItems?.length, root.tray?.adaptiveBarFolded, root.tray?.adaptiveBarFoldUnit, root.tray?.adaptiveBarOverflowOverhead]
    onInputsChanged: settleTimer.restart()

    Timer {
        id: settleTimer
        interval: 40
        onTriggered: root.refit()
    }

    function refit() {
        if (!root.middle || !root.leftSide || !root.rightSide || !root.rightContent || !root.rightRow) {
            root.fold = 0;
            root.side = root.sideMax;
            root.overflow = 0;
            return;
        }
        const unit = root.trayFoldable ? root.tray.adaptiveBarFoldUnit : 0;
        const overhead = root.trayFoldable ? root.tray.adaptiveBarOverflowOverhead : 0;
        const folded = root.trayFoldable ? root.tray.adaptiveBarFolded : 0;
        const next = Fit.settle({
            barWidth: root.barWidth,
            coreWidth: root.middle.width - root.leftSide.width - root.rightSide.width,
            sideMax: root.sideMax,
            sideMin: Math.max(root.rightContent.implicitWidth, root.leftMin),
            rightNeed: Fit.unfoldedNeed(root.rightRow.implicitWidth, folded, unit, overhead),
            foldable: root.trayFoldable ? root.tray.pinnedItems.length : 0,
            foldUnit: unit,
            foldOverhead: overhead
        }, {
            fold: root.fold,
            side: root.side
        }, Fit.HYSTERESIS);
        root.fold = next.fold;
        root.side = next.side;
        root.overflow = next.overflow;
    }
}
