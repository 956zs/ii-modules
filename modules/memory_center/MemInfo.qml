import QtQuick
import Quickshell.Io

/*
 * /proc/meminfo poller (instance, not a singleton — IIMP modules pass
 * instances). Derives the composition the visuals are built on. The
 * taxonomy is exact by construction, not by adding cache fields together
 * (Cached includes shmem, which is NOT reclaimable — summing
 * Cached+Buffers+SReclaimable double-counts and overstates):
 *
 *   in use       = MemTotal - MemAvailable   (what the kernel cannot hand out)
 *   reclaimable  = MemAvailable - MemFree    (page cache/buffers/slab it would
 *                                             reclaim under pressure)
 *   free         = MemFree
 *
 * The three sum to MemTotal exactly, so the stacked composition bar never
 * lies about the whole.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property int updateInterval: 2000
    // Polling gate: with the bar entry hidden and the panel closed there is
    // no consumer, so the owner turns this off. Resample immediately on
    // reactivation — the first Timer tick is otherwise a full interval away.
    property bool active: true
    onActiveChanged: if (active) resample()

    // kB, straight from /proc/meminfo.
    property real memTotal: 0
    property real memFree: 0
    property real memAvailable: 0
    property real swapTotal: 0
    property real swapFree: 0
    property real dirty: 0

    readonly property real usedKb: Math.max(0, memTotal - memAvailable)
    readonly property real reclaimKb: Math.max(0, memAvailable - memFree)
    readonly property real freeKb: memFree
    readonly property real swapUsedKb: Math.max(0, swapTotal - swapFree)
    readonly property real usedFrac: memTotal > 0 ? usedKb / memTotal : 0

    function fmt(kb) {
        if (kb >= 1024 * 1024) {
            const g = kb / (1024 * 1024)
            return `${g >= 10 ? g.toFixed(1) : g.toFixed(2)} GiB`
        }
        return `${Math.round(kb / 1024)} MiB`
    }

    // Compact form for the process blocks ("1.2G", "384M").
    function fmtShort(kb) {
        if (kb >= 1024 * 1024)
            return `${(kb / (1024 * 1024)).toFixed(1)}G`
        return `${Math.round(kb / 1024)}M`
    }

    function parse(t) {
        const get = k => {
            const m = t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m"))
            return m ? Number(m[1]) : 0
        }
        const total = get("MemTotal")
        if (total <= 0)
            return // torn/empty read: keep the previous sample
        memTotal = total
        memFree = get("MemFree")
        memAvailable = get("MemAvailable")
        swapTotal = get("SwapTotal")
        swapFree = get("SwapFree")
        dirty = get("Dirty")
    }

    // Immediate re-read, used to measure before/after deltas of cleanups.
    function resample() {
        fileMeminfo.reload()
        parse(fileMeminfo.text())
    }

    Timer {
        interval: 1
        running: root.active
        repeat: true
        onTriggered: {
            fileMeminfo.reload()
            root.parse(fileMeminfo.text())
            interval = root.updateInterval
        }
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
}
