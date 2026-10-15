// Vendored from lib/ConfigLoader.template.qml (golden master; see
// lib/README.md). Simple variant: the bar widget is the owner (this module
// has no window slot); the settings fragment is a read-mostly consumer.
import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/memory_center.json. Settings only —
 * this module keeps no accounting state, everything else is live data.
 */
FileView {
    id: root

    // True once the first load (or materialized defaults) completed.
    property bool ready: false
    // Exactly one instance (the bar widget's) materialises defaults into the
    // file; read-only consumers like the settings fragment must not write
    // stale snapshots over it.
    property bool owner: false
    // Guards the reload/write echo: adapter updates during materialization
    // must not be written back, or every external change makes every
    // instance (per-monitor bars + settings) write the file again.
    property bool materializing: true

    path: Directories.shellConfig + "/modules/memory_center.json"
    watchChanges: true
    blockWrites: true
    atomicWrites: true

    onFileChanged: {
        root.materializing = true;
        reload();
    }
    onAdapterUpdated: {
        if (!root.materializing)
            writeAdapter();
    }
    // A config file written by an older version misses the keys added since,
    // and the adapter yields type zero values for absent keys rather than the
    // declared defaults — write back on load so every option is in the file.
    onLoaded: {
        root.materializing = false;
        if (root.owner)
            writeAdapter();
        root.ready = true;
    }
    onLoadFailed: error => {
        if (error !== FileViewError.FileNotFound)
            return;
        root.materializing = false;
        if (root.owner)
            writeAdapter();
        root.ready = true;
    }

    property alias options: adapterItem
    adapter: JsonAdapter {
        id: adapterItem
        // Show the widget in the bar. Off frees bar space; the detail panel
        // stays reachable via the sidebar tile or IPC, and nothing polls
        // while both the bar entry and the panel are hidden.
        property bool showBar: true
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
