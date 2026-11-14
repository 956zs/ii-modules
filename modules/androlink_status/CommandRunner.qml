import QtQuick
import Quickshell
import Quickshell.Io
import "StatusLogic.js" as Logic

/*
 * Runs one androlink CLI action at a time with a fixed argv (never a shell
 * string) and reports how it ended. The action flags only forward a request
 * to the running androlink and exit, so their exit code is meaningful;
 * opening androlink may start the app itself, so it is spawned detached and
 * never tied to this object's lifetime.
 */
Item {
    id: root

    // True while an action process runs.
    readonly property bool busy: proc.running || root.awaitingExit
    // Flag of the last action ("" = open androlink).
    property string lastFlag: ""
    // Logic.exitKind() of the last finished action ("" = success), or
    // "timeout" when the watchdog stopped it.
    property string outcome: ""
    // Exit code of the last finished action.
    property int lastExitCode: 0
    // An action still running after this many seconds is stopped and
    // reported as failed (a hung androlink must not lock the panel).
    property int timeoutSecs: 15

    property bool awaitingExit: false

    signal finished(string flag, string outcome)

    // Starts `argv` for `flag`. Returns false when busy or argv is null.
    function run(flag, argv) {
        if (!argv || argv.length === 0 || root.busy)
            return false;
        root.lastFlag = flag;
        root.outcome = "";
        if (flag === "") {
            Quickshell.execDetached(argv);
            root.finished(flag, "");
            return true;
        }
        root.awaitingExit = true;
        proc.command = argv;
        proc.running = true;
        watchdog.restart();
        return true;
    }

    function clear() {
        root.outcome = "";
    }

    function settle(kind, code) {
        watchdog.stop();
        root.awaitingExit = false;
        root.lastExitCode = code;
        root.outcome = kind;
        root.finished(root.lastFlag, kind);
    }

    Process {
        id: proc
        // A process that fails to start reports running=false without an
        // exited signal on some Quickshell versions: settle it on the next
        // turn of the event loop unless exited arrived first.
        onRunningChanged: {
            if (!running && root.awaitingExit)
                startFailure.restart();
        }
        onExited: (exitCode, exitStatus) => {
            startFailure.stop();
            if (root.awaitingExit)
                root.settle(Logic.exitKind(exitCode, true), exitCode);
        }
    }

    Timer {
        id: watchdog
        interval: Math.max(1, root.timeoutSecs) * 1000
        onTriggered: {
            if (!root.awaitingExit)
                return;
            root.settle("timeout", -1);
            proc.running = false;
        }
    }

    Timer {
        id: startFailure
        interval: 0
        onTriggered: {
            if (!proc.running && root.awaitingExit)
                root.settle(Logic.exitKind(0, false), -1);
        }
    }
}
