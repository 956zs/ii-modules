// Vendored from lib/ConfigLoader.template.qml (golden master; see
// lib/README.md). Simple variant: the window-slot entry (loaded once) is the
// owner; bar/settings copies are read-mostly consumers.
import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/battery_trend.json. Never touches the
 * shell's config.json.
 *
 * The entire battery history lives in ONE JSON-string blob (histState),
 * updated by a single adapter assignment. Per-field storage is unsafe here:
 * every assignment rewrites the whole file, watchChanges reloads race with
 * our own writes, and iimod's hot reload briefly runs old and new instances
 * side by side — a multi-field flush can be read back as a torn snapshot.
 * One assignment per blob makes a torn adapter write structurally
 * impossible; atomicWrites (temp file + rename) additionally keeps the
 * on-disk file all-or-nothing for concurrent watchers, and blockWrites makes
 * writeAdapter() synchronous so a flush has really hit disk when it returns.
 *
 * `property var` inside a JsonAdapter is forbidden: Quickshell's
 * deserializer segfaults writing a JSON object into it. Hence the string.
 */
FileView {
    id: root

    // False until the file content (or its confirmed absence) is in the
    // adapter. History must not initialise from default zeroes.
    property bool ready: false
    // Exactly one instance (the window-slot entry, loaded once) materialises
    // defaults into the file and hosts the history flushes. Read-only
    // consumers (settings fragment, per-monitor bars, stock popup) must not
    // write stale snapshots over the owner's state.
    property bool owner: false
    // Guards the reload/write echo: adapter updates during materialization
    // must not be written back, or every reload triggers a write loop.
    property bool materializing: true

    path: Directories.shellConfig + "/modules/battery_trend.json"
    watchChanges: true
    blockWrites: true
    atomicWrites: true

    onFileChanged: {
        root.materializing = true
        reload()
    }
    onAdapterUpdated: {
        if (!root.materializing)
            writeAdapter()
    }
    // Materialise the merged adapter after every successful load: a file
    // written by an older version misses keys added since, and the adapter
    // yields type zero values for absent keys, not the declared defaults.
    onLoaded: {
        root.materializing = false
        if (root.owner)
            writeAdapter()
        root.ready = true
    }
    onLoadFailed: error => {
        if (error !== FileViewError.FileNotFound)
            return
        root.materializing = false
        if (root.owner)
            writeAdapter()
        root.ready = true
    }

    property alias options: adapterItem
    adapter: JsonAdapter {
        id: adapterItem
        // Seconds between history samples (UI clamps to 15..600).
        property int samplingIntervalSec: 60
        // Retention tiers. Raw 24 h @ interval is always kept (it feeds the
        // sparkline and the 24 h chart); these gate the long tails.
        property bool keepHourly: true    // 30 days of hourly aggregates
        property bool keepDaily: true     // 365 days of daily aggregates + health snapshots
        property bool keepSessions: true  // charge/discharge session records
        // sysfs battery to read; "auto" resolves via UPower's nativePath,
        // then falls back to probing BAT0/BAT1/….
        property string batteryName: "auto"
        // Bar presentation. The stock bar already has a battery gauge, so
        // this module claims NO bar space by default — the sidebar tile /
        // IPC toggle is the primary panel entry. Opting into showBar gives
        // a sparkline-only pill (host layout skips the root while hidden;
        // sampling and persistence run either way); showPercent adds the
        // number on top of that.
        property bool showBar: false
        property bool showPercent: false

        // History blob, managed by BatteryLogic, flushed at most once a
        // minute — not a user setting.
        // {v, raw:[[t,pct,W,cls]], hourly:[[t,min,max,avg,avgW,chgFrac,disPct,disSec]],
        //  daily:[same], sessions:[[kind,t0,t1,p0,p1]], health:[[day,fullPct,cycles]],
        //  cur:{h,d,s: in-progress accumulators}}
        property string histState: ""
    }
}
