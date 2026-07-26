import QtQuick
import Quickshell.Io

/*
 * Privileged cleanup runner. pkexec first — the ii shell ships its own
 * polkit agent (modules/ii/polkit), so this raises the shell's auth dialog.
 * If pkexec fails for any reason other than the user dismissing the dialog
 * (exit 126), one fallback attempt goes through `sudo -A` (askpass). Both
 * failing surfaces the collected stderr inline; nothing retries silently.
 *
 * After a successful run the meminfo sample is re-read and the honest delta
 * reported: for swap, how much left swap; for caches, how much MemFree grew.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    required property var mem

    // "idle" | "running" | "done" | "error" (`state` is taken by Item).
    property string phase: "idle"
    property string lastAction: "" // "swap" | "cache"
    property string errorText: ""
    property real freedKb: 0

    property string script: ""
    property real beforeVal: 0
    property bool triedSudo: false
    property string pkexecStderr: ""
    property string sudoStderr: ""

    function trimSwap() {
        run("swap", "swapoff -a && swapon -a")
    }

    function dropCaches() {
        run("cache", "sync; echo 3 > /proc/sys/vm/drop_caches")
    }

    function run(action, cmd) {
        if (phase === "running")
            return
        lastAction = action
        script = cmd
        beforeVal = action === "swap" ? mem.swapUsedKb : mem.memFree
        errorText = ""
        pkexecStderr = ""
        sudoStderr = ""
        triedSudo = false
        freedKb = 0
        phase = "running"
        pkexecProc.running = true
    }

    Process {
        id: pkexecProc
        command: ["pkexec", "sh", "-c", root.script]
        stderr: StdioCollector {
            onStreamFinished: root.pkexecStderr = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                settleTimer.start()
                return
            }
            if (exitCode === 126) {
                // Auth dialog dismissed — the user said no; don't nag via sudo.
                root.phase = "idle"
                return
            }
            if (!root.triedSudo) {
                root.triedSudo = true
                sudoProc.running = true
                return
            }
            failTimer.fallback = `pkexec exited ${exitCode}`
            failTimer.start()
        }
    }

    Process {
        id: sudoProc
        command: ["sudo", "-A", "sh", "-c", root.script]
        stderr: StdioCollector {
            onStreamFinished: root.sudoStderr = text.trim()
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                settleTimer.start()
                return
            }
            failTimer.fallback = `sudo exited ${exitCode}`
            failTimer.start()
        }
    }

    // Compose the error slightly late: onExited can beat the StdioCollector,
    // and the stderr text is the useful part of the message.
    Timer {
        id: failTimer
        property string fallback: ""
        interval: 200
        onTriggered: {
            root.errorText = [root.pkexecStderr, root.sudoStderr].filter(s => s !== "").join("\n") || failTimer.fallback
            root.phase = "error"
        }
    }

    // Give the kernel a beat to settle before measuring the delta.
    Timer {
        id: settleTimer
        interval: 800
        onTriggered: {
            root.mem.resample()
            const after = root.lastAction === "swap" ? root.mem.swapUsedKb : root.mem.memFree
            root.freedKb = root.lastAction === "swap"
                ? Math.max(0, root.beforeVal - after)
                : Math.max(0, after - root.beforeVal)
            root.phase = "done"
        }
    }
}
