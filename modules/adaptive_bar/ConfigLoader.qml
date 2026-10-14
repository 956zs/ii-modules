// Vendored from lib/ConfigLoader.template.qml (golden master; see
// lib/README.md in the ii-modules repository). Each module ships its own
// copy — IIMP modules are self-contained and never import another module's
// files. Keep the skeleton invariants; tools/lib-sync/check-configloader.mjs
// verifies every first-party copy.
//
// Simple variant: every instance watches and materializes values, and only
// the elected owner instance writes defaults back. Modules that persist
// runtime accounting from multiple surfaces need the owner-elected
// intent-queue variant instead; see modules/network_traffic/ConfigLoader.qml.
import Quickshell.Io
import qs.modules.common

FileView {
    id: root

    // True once the first load (or materialized defaults) completed.
    property bool ready: false
    // Exactly one instance per shell process may write; the window-slot entry
    // (loaded once) should own writes, bar-slot copies are per-monitor.
    property bool owner: false
    // Guards the reload/write echo: adapter updates during materialization
    // must not be written back, or every reload triggers a write loop.
    property bool materializing: true

    path: Directories.shellConfig + "/modules/adaptive_bar.json"
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
    onLoaded: {
        if (adapterItem.centerSideMaxWidth < 190 || adapterItem.centerSideMaxWidth > 360)
            adapterItem.centerSideMaxWidth = 360;
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

        // Upper bound for both centre side groups of the horizontal bar.
        // 360 equals the stock verbose width, so wide screens stay stock.
        property int centerSideMaxWidth: 360
    }
}
