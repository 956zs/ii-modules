import QtQuick
import Quickshell.Io
import "AulaKeysLogic.js" as Logic

/*
 * Runs `aulactl feed --keys ...` while `active` and turns its NDJSON stdout
 * into a per-key model plus counters. The feed holds the keyboard's device
 * lock, so it runs only while the overlay is shown: clearing `active` sends
 * SIGTERM. An unexpected exit restarts it with exponential backoff; a
 * `hello` (board connected) resets the backoff.
 */
Item {
    id: root

    property bool active: false
    // Executable name or path; looked up in the shell's PATH.
    property string binary: "aulactl"
    // Key codes in display order (already validated by Logic.parseKeyList).
    property var keys: Logic.DEFAULT_KEYS
    // Passed as --depth-hz when > 0; 0 keeps the feed's default.
    property int depthHz: 0

    // One row per configured key:
    // { code, label, mm, point, pressed, count, known }.
    readonly property alias model: keyModel
    property real maxMm: 0
    property string product: ""
    // "" (live), "starting", "waiting", "busy", "lost", "error", "restarting".
    property string status: ""
    property string errorText: ""
    property int total: 0
    property int peak: 0
    property int kpsNow: 0

    property var stats: Logic.newStats()
    property var indexByCode: ({})
    property int attempt: 0
    // Set while a deliberate stop (key list changed) should start again
    // immediately instead of going through the backoff.
    property bool restartNow: false
    property string lastStderr: ""

    function rebuildModel() {
        keyModel.clear();
        const index = {};
        for (let i = 0; i < root.keys.length; i++) {
            const code = root.keys[i];
            index[code] = i;
            keyModel.append({
                code: code,
                label: Logic.keyLabel(code),
                mm: 0,
                point: 0,
                pressed: false,
                count: root.stats.counts[code] || 0,
                known: false
            });
        }
        root.indexByCode = index;
    }

    function releaseAll() {
        for (let i = 0; i < keyModel.count; i++) {
            keyModel.setProperty(i, "mm", 0);
            keyModel.setProperty(i, "pressed", false);
        }
    }

    function resetCounts() {
        Logic.resetCounts(root.stats);
        for (let i = 0; i < keyModel.count; i++)
            keyModel.setProperty(i, "count", 0);
        root.total = 0;
        root.peak = 0;
        root.kpsNow = 0;
    }

    function setStatus(kind) {
        if (kind === root.status)
            return;
        root.status = kind;
        // One log line per change of the board state, never one per feed
        // line; the start/retry cycle is logged once in onRunningChanged.
        if (kind === "waiting" || kind === "busy" || kind === "lost" || kind === "error")
            console.info(`[aula_keys] feed ${kind}`);
    }

    function handle(line) {
        const ev = Logic.parseLine(line);
        if (!ev)
            return;
        const wall = Date.now();
        const i = root.indexByCode[ev.key];
        switch (ev.type) {
        case "hello":
            root.attempt = 0;
            root.maxMm = ev.maxMm;
            root.product = ev.product;
            root.releaseAll();
            for (const key of ev.keys) {
                const k = root.indexByCode[key.code];
                if (k === undefined)
                    continue;
                keyModel.setProperty(k, "label", key.label);
                keyModel.setProperty(k, "point", key.point);
                keyModel.setProperty(k, "known", true);
            }
            root.setStatus("");
            break;
        case "status":
            if (ev.state === "lost")
                root.releaseAll();
            root.setStatus(Logic.statusKind(ev));
            break;
        case "error":
            root.errorText = ev.msg;
            root.setStatus("error");
            break;
        case "depth":
            Logic.syncClock(root.stats, ev.t, wall);
            if (i !== undefined)
                keyModel.setProperty(i, "mm", ev.mm);
            break;
        case "press":
            root.kpsNow = Logic.recordPress(root.stats, ev.key, ev.t, wall);
            root.total = root.stats.total;
            root.peak = root.stats.peak;
            if (i !== undefined) {
                keyModel.setProperty(i, "pressed", true);
                keyModel.setProperty(i, "count", root.stats.counts[ev.key]);
            }
            break;
        case "release":
            Logic.syncClock(root.stats, ev.t, wall);
            if (i !== undefined)
                keyModel.setProperty(i, "pressed", false);
            break;
        }
    }

    function start() {
        if (proc.running || !root.active)
            return;
        root.lastStderr = "";
        if (root.status === "" || root.status === "restarting")
            root.setStatus("starting");
        proc.running = true;
    }

    // New arguments: restart a running feed at once, and skip a pending
    // backoff (the change may be the fix for a failing command).
    function relaunch() {
        root.attempt = 0;
        if (proc.running) {
            root.restartNow = true;
            proc.running = false;
        } else if (restartTimer.running) {
            restartTimer.stop();
            root.start();
        }
    }

    onKeysChanged: {
        root.rebuildModel();
        Qt.callLater(root.relaunch);
    }
    // Deferred so proc.command has re-evaluated before the next start.
    onDepthHzChanged: Qt.callLater(root.relaunch)
    onBinaryChanged: Qt.callLater(root.relaunch)
    onActiveChanged: {
        if (root.active) {
            root.attempt = 0;
            root.setStatus("starting");
            root.start();
        } else {
            restartTimer.stop();
            root.restartNow = false;
            proc.running = false;
        }
    }
    Component.onCompleted: root.rebuildModel()

    ListModel {
        id: keyModel
    }

    Process {
        id: proc
        command: [root.binary].concat(Logic.feedArgs(root.keys, root.depthHz))
        stdout: SplitParser {
            onRead: data => root.handle(data)
        }
        // Human-readable only; kept so a crash loop leaves one hint in the log.
        stderr: SplitParser {
            onRead: data => root.lastStderr = data
        }
        // Also fires when the binary fails to start (no `exited` then).
        onRunningChanged: {
            if (running)
                return;
            root.releaseAll();
            root.kpsNow = 0;
            Logic.resetWindow(root.stats);
            if (!root.active) {
                root.setStatus("");
                return;
            }
            if (root.restartNow) {
                root.restartNow = false;
                root.start();
                return;
            }
            const delay = Logic.backoffMs(root.attempt);
            root.attempt += 1;
            if (root.attempt === 1)
                console.warn(`[aula_keys] feed exited, retrying in ${delay} ms${root.lastStderr !== "" ? ": " + root.lastStderr : ""}`);
            root.setStatus("restarting");
            restartTimer.interval = delay;
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        repeat: false
        onTriggered: root.start()
    }

    // Lets the KPS figure decay while no keys are pressed.
    Timer {
        interval: 100
        repeat: true
        running: root.active && root.kpsNow > 0
        onTriggered: root.kpsNow = Logic.kps(root.stats, Date.now())
    }
}
