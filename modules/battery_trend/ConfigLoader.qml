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
 * One assignment per blob makes a torn read structurally impossible
 * (established in network_traffic; see its README).
 *
 * `property var` inside a JsonAdapter is forbidden: Quickshell's
 * deserializer segfaults writing a JSON object into it. Hence the string.
 */
FileView {
    id: root
    // False until the file content (or its confirmed absence) is in the
    // adapter. History must not initialise from default zeroes.
    property bool ready: false
    // Exactly one instance (the primary screen's bar widget) materialises
    // defaults into the file and hosts the history flushes. Read-only
    // consumers (settings fragment, secondary screens) must not write stale
    // snapshots over the owner's state.
    property bool owner: false

    path: Directories.shellConfig + "/modules/battery_trend.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    // Materialise the merged adapter after every successful load: a file
    // written by an older version misses keys added since, and the adapter
    // yields type zero values for absent keys, not the declared defaults.
    onLoaded: {
        if (root.owner) writeAdapter()
        root.ready = true
    }
    onLoadFailed: error => {
        if (error == FileViewError.FileNotFound) {
            if (root.owner) writeAdapter()
            root.ready = true
        }
    }
    // Primary-screen election can settle after the first load (the window
    // attaches to its screen asynchronously); materialise then.
    onOwnerChanged: if (root.owner && root.ready) writeAdapter()

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

        // History blob, managed by BatteryLogic, flushed at most once a
        // minute — not a user setting.
        // {v, raw:[[t,pct,W,cls]], hourly:[[t,min,max,avg,avgW,chgFrac,disPct,disSec]],
        //  daily:[same], sessions:[[kind,t0,t1,p0,p1]], health:[[day,fullPct,cycles]],
        //  cur:{h,d,s: in-progress accumulators}}
        property string histState: ""
    }
}
