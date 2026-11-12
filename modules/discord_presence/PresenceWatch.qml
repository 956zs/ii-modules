import QtQuick
import Quickshell
import Quickshell.Io
import "PresenceLogic.js" as Logic

/*
 * Keeps `discord-rpc-proxy watch` running and exposes the latest status.
 * The watch process prints one JSON line at once and one per change; when
 * it exits (daemon not running, binary missing, daemon restarted) the state
 * drops to "down" and the stream is retried: soon after a stream that was
 * working, every 10 s otherwise. `toggle()` runs `discord-rpc-proxy toggle`;
 * the new state then arrives through the stream.
 */
Item {
    id: root

    // Raw setting; resolved (trimmed, ~/ expanded) before use.
    property string binary: Logic.DEFAULT_BINARY
    // Set while the hover popup is open: the only place running times show.
    property bool popupOpen: false
    // Hide the pill while nothing is detected and presence is not paused.
    property bool hideWhenIdle: false

    readonly property string executable: Logic.resolveBinary(root.binary, Quickshell.env("HOME") ?? "")

    property var record: Logic.downState()
    // Wall clock (s) when the current record arrived, for play time growth.
    property real receivedSecs: Date.now() / 1000
    property real nowSecs: Date.now() / 1000

    readonly property string kind: Logic.kind(root.record)
    readonly property bool shown: Logic.shownFor(root.record, root.hideWhenIdle)
    readonly property string marker: Logic.marker(root.record)
    readonly property string barText: Logic.barText(root.record)
    readonly property var game: root.record.game
    readonly property int elapsedSecs: Logic.elapsed(root.record, root.nowSecs)
    readonly property int playtimeSecs: Logic.playtimeNow(root.record, root.receivedSecs, root.nowSecs)
    readonly property bool toggling: toggleProc.running

    // Whether the current stream delivered a status line.
    property bool hadLine: false
    // Consecutive failed starts; only the first one is logged.
    property int failures: 0
    // Set when a deliberate stop (binary changed) should start again at once.
    property bool restartNow: false
    property string lastStderr: ""

    function handle(line) {
        const next = Logic.parseStatus(line);
        if (!next)
            return;
        if (!root.hadLine && root.failures > 0)
            console.info("[discord_presence] watch connected");
        root.hadLine = true;
        root.failures = 0;
        const now = Date.now() / 1000;
        root.receivedSecs = now;
        root.nowSecs = now;
        root.record = next;
    }

    function start() {
        if (watchProc.running)
            return;
        root.hadLine = false;
        root.lastStderr = "";
        watchProc.running = true;
    }

    // Skips a pending backoff, e.g. after the owner started the daemon.
    function retryNow() {
        retryTimer.stop();
        root.start();
    }

    function relaunch() {
        if (watchProc.running) {
            root.restartNow = true;
            watchProc.running = false;
        } else {
            root.retryNow();
        }
    }

    // Left click: toggle pause; while the daemon is down, retry at once.
    function toggle() {
        if (!root.record.up) {
            root.retryNow();
            return;
        }
        if (!toggleProc.running)
            toggleProc.running = true;
    }

    // Deferred so watchProc.command has re-evaluated before the next start.
    onExecutableChanged: Qt.callLater(root.relaunch)
    onPopupOpenChanged: {
        if (root.popupOpen)
            root.nowSecs = Date.now() / 1000;
    }
    Component.onCompleted: root.start()

    Process {
        id: watchProc
        command: [root.executable, "watch"]
        stdout: SplitParser {
            onRead: data => root.handle(data)
        }
        // Human-readable only; kept so a failure leaves one hint in the log.
        stderr: SplitParser {
            onRead: data => root.lastStderr = data
        }
        // Also fires when the binary fails to start (no `exited` then).
        onRunningChanged: {
            if (running)
                return;
            root.record = Logic.downState();
            if (root.restartNow) {
                root.restartNow = false;
                root.start();
                return;
            }
            const delay = Logic.retryDelayMs(root.hadLine);
            if (root.hadLine)
                console.info("[discord_presence] watch ended, reconnecting");
            else {
                root.failures += 1;
                if (root.failures === 1)
                    console.info(`[discord_presence] daemon not reachable, retrying every ${delay / 1000} s${root.lastStderr !== "" ? ": " + root.lastStderr : ""}`);
            }
            root.hadLine = false;
            retryTimer.interval = delay;
            retryTimer.restart();
        }
    }

    // Output is a human summary; the watch stream carries the new state.
    Process {
        id: toggleProc
        command: [root.executable, "toggle"]
    }

    Timer {
        id: retryTimer
        repeat: false
        onTriggered: root.start()
    }

    // Second hand for the popup's elapsed and play time rows.
    Timer {
        interval: 1000
        repeat: true
        running: Logic.needsTicker(root.record, root.popupOpen)
        onTriggered: root.nowSecs = Date.now() / 1000
    }
}
