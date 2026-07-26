import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Top-RSS process sampler. Polls ps only while `active` (the detail panel
 * is open); nothing runs otherwise. Kernel threads (RSS 0) are dropped and
 * the tail beyond `topCount` folds into one "other" bucket, so the block
 * view keeps a readable series count instead of generating more rectangles.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool active: false
    property int updateInterval: 4000
    property int topCount: 12

    // [{pid, user, rss (kB), name, own}], RSS-descending, length <= topCount.
    // (`top` itself is Item's FINAL anchor line — hence the longer name.)
    property var topProcs: []
    property real otherKb: 0
    property int otherCount: 0
    property real sampledKb: 0
    // Bumped per sample so computed bindings re-evaluate.
    property int revision: 0

    // SIGTERM is only offered for the user's own processes.
    property string me: Quickshell.env("USER") ?? ""

    function pollNow() {
        if (!psProc.running)
            psProc.running = true
    }

    Timer {
        running: root.active
        interval: root.updateInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollNow()
    }

    // USER can be absent in the compositor's environment; resolve once.
    Process {
        id: idProc
        running: root.me === ""
        command: ["id", "-un"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() !== "") root.me = text.trim()
        }
    }

    Process {
        id: psProc
        command: ["ps", "-eo", "pid=,euser:32=,rss=,comm=", "--sort=-rss"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    function parse(text) {
        const rows = []
        let total = 0
        for (const line of text.split("\n")) {
            // pid user rss comm — comm may contain spaces, so it is the rest.
            const m = line.match(/^\s*(\d+)\s+(\S+)\s+(\d+)\s+(.*\S)\s*$/)
            if (!m) continue
            const rss = Number(m[3])
            if (rss <= 0) continue
            total += rss
            rows.push({
                pid: Number(m[1]),
                user: m[2],
                rss,
                name: m[4],
                own: root.me !== "" && m[2] === root.me
            })
        }
        rows.sort((a, b) => b.rss - a.rss)
        const n = Math.max(1, root.topCount)
        let other = 0
        for (const r of rows.slice(n))
            other += r.rss
        root.topProcs = rows.slice(0, n)
        root.otherKb = other
        root.otherCount = Math.max(0, rows.length - n)
        root.sampledKb = total
        root.revision++
    }
}
