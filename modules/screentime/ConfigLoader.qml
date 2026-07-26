import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/screentime.json. Never touches the
 * shell's config.json.
 *
 * The entire usage history lives in ONE JSON-string property (histState),
 * updated by a single adapter assignment. Per-field storage is unsafe here:
 * every assignment rewrites the whole file, watchChanges reloads race with
 * our own writes, and iimod's hot reload briefly runs old and new instances
 * side by side — a multi-field flush could be read back as a torn snapshot.
 * One assignment per blob makes a torn read structurally impossible.
 * (Learned the hard way in network_traffic; see its README.)
 */
FileView {
    id: root
    // False until the file content (or its confirmed absence) is in the
    // adapter. Accounting must not initialise from default zeroes.
    property bool ready: false
    // Exactly one instance (the window slot's logic host) materialises
    // defaults into the file and owns the accounting flushes. Read-only
    // consumers (bar widget, settings fragment) must not write stale
    // snapshots over the owner's state.
    property bool owner: false

    path: Directories.shellConfig + "/modules/screentime.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    // Materialise the merged adapter after every successful load: a config
    // file written by an older version misses keys added since, and the
    // adapter yields type zero values for absent keys, not the declared
    // defaults. Writing back on load keeps upgrades honest.
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

    property alias options: adapterItem
    adapter: JsonAdapter {
        id: adapterItem

        // Comma-separated appId/class substrings that are never accounted
        // (matched case-insensitively).
        property string excludedApps: ""

        // A wall-clock jump larger than this between accounting events is
        // treated as suspend/AFK and credited to nothing.
        property int idleGapSec: 90

        // Keep the 30-day daily history. Off wipes and stops recording
        // anything older than today.
        property bool keepHistory: true

        // Usage history blob, managed by ScreentimeLogic in the window slot,
        // flushed at most once a minute — not a user setting.
        // {v, day:{k,apps:{id:sec},hours:[24]}, days:[{k,total,apps:[{n,s}]}]}
        // NEVER a `property var` — Quickshell's deserializer segfaults
        // writing a JSON object into one. JSON string + parse at the reader.
        property string histState: ""
    }
}
