import QtQuick
import Quickshell
import qs.modules.common
import qs.mod.battery_trend

/*
 * Module-owned replacement for the stock BatteryPopup. The stock indicator
 * creates this wrapper through a Tier B insert-only patch. This instance is a
 * reader only: the hidden bar-slot primary remains the sole history writer.
 */
Item {
    id: root
    width: 0
    height: 0

    property Item hoverTarget: null
    property bool suppressed: false

    function openDetails() {
        // Close the hover popup before opening the focusable detail panel.
        root.suppressed = true
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "--any-display",
                                 "call", "battery_trend", "toggle"])
    }

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

    BatteryPopup {
        id: popup
        hoverTarget: root.suppressed || Config.options.bar.tooltips.clickToShow
                     ? null : root.hoverTarget
        logic: logic
    }

    Connections {
        target: root.hoverTarget
        function onContainsMouseChanged() {
            if (!root.hoverTarget?.containsMouse)
                root.suppressed = false
        }
    }
}
