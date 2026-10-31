import QtQuick
import Quickshell
import Quickshell.Io
import "OsuStateLogic.js" as OsuLogic

/*
 * osu! state reader, trimmed from modules/osu_indicator/OsuState.qml: reads
 * $XDG_RUNTIME_DIR/osu-state.json written atomically by the osu-state
 * daemon, which is the single place that detects anything. A missing or
 * malformed file reads as "off".
 */
Item {
    id: root

    // False while no mode needs osu! (always/off) to stop the fallback poll.
    property bool active: true

    readonly property string path: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return runtime !== "" ? `${runtime}/osu-state.json` : "";
    }

    property var record: OsuLogic.offState()
    readonly property string state: record.state
    // Unix seconds the current state began; a new value while playing is a
    // new map.
    readonly property int since: record.since

    FileView {
        id: file
        path: root.active ? root.path : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.record = OsuLogic.parseState(text())
        onLoadFailed: root.record = OsuLogic.offState()
    }

    // The daemon replaces the file by rename, which some watchers report
    // once and then lose; a 5 s re-read keeps the state honest.
    Timer {
        interval: 5000
        repeat: true
        running: root.active && root.path !== ""
        onTriggered: file.reload()
    }
}
