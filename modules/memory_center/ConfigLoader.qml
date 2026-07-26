import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/memory_center.json. Settings only —
 * this module keeps no accounting state, everything else is live data.
 */
FileView {
    id: root
    // False until the file content (or its confirmed absence) is loaded.
    property bool ready: false
    // Exactly one instance (the bar widget's) materialises defaults into the
    // file; read-only consumers like the settings fragment must not write
    // stale snapshots over it.
    property bool owner: false

    path: Directories.shellConfig + "/modules/memory_center.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    // A config file written by an older version misses the keys added since,
    // and the adapter yields type zero values for absent keys rather than the
    // declared defaults — write back on load so every option is in the file.
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
        // /proc/meminfo poll (bar widget + popup), ms. Cheap: one file read.
        property int meminfoInterval: 2000
        // ps poll while the detail panel is open, ms. Nothing runs when closed.
        property int procInterval: 4000
        // Show the used percentage next to the bar icon (off = icon only,
        // the pressure colour still carries the state).
        property bool showBarPercent: true
        // Process blocks in the panel; the tail beyond this folds into "Other".
        property int blockCount: 12
        // Bar colour starts drifting toward the error tone at this used %.
        property int warnPercent: 85
    }
}
