import Quickshell
import Quickshell.Io
import qs
import qs.mod.screentime

/*
 * Window-slot entry — the single place the accountant lives. The window slot
 * is instantiated exactly once by the module host (bar entries are per
 * bar/monitor and would double-count focus time), so this Scope owns the
 * config file, the focus accounting, and the detail panel plus its IPC
 * surface (`qs -c ii ipc call screentime toggleDetails`).
 */
Scope {
    id: root

    // Sole owner: materialises defaults into the file and hosts the
    // accounting flushes. Bar/settings loaders are read-only consumers.
    ConfigLoader {
        id: cfg
        owner: true
    }

    ScreentimeLogic {
        id: logic
        store: cfg.options
        storeReady: cfg.ready
    }

    // Feeds the separate "AI agents working" dimension into the same
    // accountant; lives here for the same single-instance reason.
    AgentMonitor {
        store: cfg.options
        logic: logic
    }

    DetailsPanel {
        id: panel
        logic: logic
    }

    IpcHandler {
        target: "screentime"

        function toggleDetails(): void {
            // Opened from the sidebar tile: drop the sidebar first so the two
            // focus grabs don't fight over who closes whom.
            GlobalStates.sidebarRightOpen = false
            panel.toggle()
        }
    }
}
