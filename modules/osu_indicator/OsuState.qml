import QtQuick
import Quickshell
import Quickshell.Io
import "OsuStateLogic.js" as Logic

/*
 * Reader for the osu-state daemon's file. Only reads: the daemon
 * ($XDG_RUNTIME_DIR/osu-state.json, written atomically by rename) is the
 * single place that detects anything. Watches the file, re-reads on change,
 * and ticks once a second only while a timer is on screen. A slow fallback
 * poll covers watchers that miss a rename-replaced inode.
 */
Item {
    id: root

    // User switches for the secondary states.
    property bool showWhenIdle: true
    property bool showWhenMenu: true
    // Whether the bar shows the timer text (drives the 1 s ticker).
    property bool showTimer: true
    // Set false while nothing is on screen to stop the fallback poll.
    property bool active: true

    readonly property string path: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return runtime !== "" ? `${runtime}/osu-state.json` : "";
    }

    property var record: Logic.offState()
    property real nowSecs: Date.now() / 1000

    readonly property string state: record.state
    readonly property bool busy: state === "playing" || state === "cooldown"
    readonly property bool shown: Logic.shownFor(state, root.showWhenIdle, root.showWhenMenu)
    readonly property int elapsedSecs: Logic.elapsed(record, nowSecs)
    readonly property int cooldownLeftSecs: Logic.cooldownLeft(record, nowSecs)
    readonly property string barText: Logic.barText(record, nowSecs, root.showTimer)
    readonly property var beatmap: Logic.splitBeatmap(record.beatmap)

    function apply(text) {
        root.record = Logic.parseState(text);
        root.nowSecs = Date.now() / 1000;
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: root.apply("")
    }

    // Second hand for the elapsed / countdown text.
    Timer {
        interval: 1000
        repeat: true
        running: root.active && Logic.needsTicker(root.record, root.showTimer)
        onTriggered: root.nowSecs = Date.now() / 1000
    }

    // Fallback poll: the daemon replaces the file by rename, which some
    // watchers report once and then lose; a 5 s re-read keeps the pill
    // honest at negligible cost.
    Timer {
        interval: 5000
        repeat: true
        running: root.active && root.path !== ""
        onTriggered: file.reload()
    }
}
