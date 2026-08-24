import Quickshell
import Quickshell.Io
import qs
import qs.mod.battery_trend

/*
 * Window-slot entry — the single place the history owner lives. The window
 * slot is instantiated exactly once by the module host, so this Scope owns
 * the config file, the sampler, the detail panel, and its IPC surface
 * (`qs -c ii ipc call battery_trend toggle`).
 *
 * Bar entries are per bar/monitor: hosting any of these singletons there
 * requires a primary-screen election, and that election re-evaluates on
 * screen changes and shell reloads. When the elected instance is torn down,
 * its IpcHandler dies with it and Quickshell does not promote a previously
 * rejected duplicate — the `battery_trend` IPC target then stays dead for
 * the rest of the session and the detail panel can no longer be opened from
 * the stock indicator or the sidebar tile. Owning everything here removes
 * the election entirely; bar instances are pure readers.
 */
Scope {
    id: root

    // Sole owner: materialises defaults into the file and hosts the history
    // flushes. Bar/settings loaders are read-only consumers.
    ConfigLoader {
        id: cfg
        owner: true
    }

    BatteryLogic {
        id: logic
        store: cfg.options
        storeReady: cfg.ready
        sampling: true
        intervalSec: {
            const v = cfg.options.samplingIntervalSec
            return v >= 15 && v <= 600 ? v : 60
        }
        keepHourly: cfg.options.keepHourly === true
        keepDaily: cfg.options.keepDaily === true
        keepSessions: cfg.options.keepSessions === true
        batteryName: cfg.options.batteryName !== "" ? cfg.options.batteryName : "auto"
        fastPoll: detailPanel.visible
    }

    DetailPanel {
        id: detailPanel
        logic: logic
    }

    IpcHandler {
        target: "battery_trend"

        function toggle(): void {
            // Opened from the sidebar tile: drop the sidebar first so the
            // two focus grabs don't fight over who closes whom.
            GlobalStates.sidebarRightOpen = false
            detailPanel.toggle()
        }
    }
}
