import QtQuick
import Quickshell
import Quickshell.Wayland

// Asks the compositor whether a Wayland idle inhibitor is in effect: the
// first monitor sees only input, the second also honours inhibitors. If only
// the first goes idle, an inhibitor is active. Driven by probe.sh.
ShellRoot {
    IdleMonitor {
        timeout: 2
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) console.log("[idleprobe] raw-idle")
    }
    IdleMonitor {
        timeout: 2
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) console.log("[idleprobe] inhib-idle")
    }
}
