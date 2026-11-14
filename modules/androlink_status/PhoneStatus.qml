import QtQuick
import Quickshell
import Quickshell.Io
import "StatusLogic.js" as Logic

/*
 * Reader for androlink's status file. Only reads: androlink writes
 * $XDG_RUNTIME_DIR/androlink/status.json atomically (temp file + rename) on
 * every change and every heartbeat. The file is watched; a slow re-read also
 * runs because watchers can lose a rename-replaced inode, the directory may
 * not exist yet, and staleness must be noticed even when nothing is written.
 */
Item {
    id: root

    // androlink's heartbeat (seconds) when the file does not publish one.
    property int heartbeatSecs: 30
    // Fallback re-read interval (seconds).
    property int pollSecs: 10

    readonly property string path: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return runtime !== "" ? `${runtime}/androlink/status.json` : "";
    }

    // Raw text of the last read; null while the file is missing or unreadable.
    property var rawText: null
    property real nowSecs: Date.now() / 1000

    readonly property var record: Logic.parseStatus(root.rawText, root.nowSecs, root.heartbeatSecs)
    readonly property bool appRunning: Logic.appRunning(root.record)
    readonly property int primaryIndex: Logic.primaryIndex(root.record)

    function refresh() {
        root.nowSecs = Date.now() / 1000;
        if (root.path !== "")
            file.reload();
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.rawText = text();
            root.nowSecs = Date.now() / 1000;
        }
        onLoadFailed: {
            root.rawText = null;
            root.nowSecs = Date.now() / 1000;
        }
    }

    Timer {
        interval: Math.max(2, root.pollSecs) * 1000
        repeat: true
        running: root.path !== ""
        onTriggered: root.refresh()
    }
}
