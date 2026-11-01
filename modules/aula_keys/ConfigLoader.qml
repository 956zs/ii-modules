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
import "AulaKeysLogic.js" as Logic

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

    path: Directories.shellConfig + "/modules/aula_keys.json"
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
        // MODULE VALIDATION: heal unknown choices and out-of-range numbers.
        const o = adapterItem;
        if (Logic.normalizeMode(o.mode) !== o.mode)
            o.mode = "playing";
        if (Logic.normalizeCorner(o.corner) !== o.corner)
            o.corner = "bottomRight";
        if (Logic.normalizeTravelStyle(o.travelStyle) !== o.travelStyle)
            o.travelStyle = "fill";
        if (Logic.normalizeKeepAfterPlay(o.keepAfterPlay) !== o.keepAfterPlay)
            o.keepAfterPlay = "results";
        if (o.scalePercent < 50 || o.scalePercent > 300)
            o.scalePercent = Logic.clamp(o.scalePercent, 50, 300, 100);
        if (o.opacityPercent < 20 || o.opacityPercent > 100)
            o.opacityPercent = Logic.clamp(o.opacityPercent, 20, 100, 90);
        if (o.marginPx < 0 || o.marginPx > 400)
            o.marginPx = Logic.clamp(o.marginPx, 0, 400, 24);
        if (o.hideDelaySecs < 0 || o.hideDelaySecs > 60)
            o.hideDelaySecs = Logic.clamp(o.hideDelaySecs, 0, 60, 3);
        if (o.depthHz < 0 || o.depthHz > 1000)
            o.depthHz = Logic.clamp(o.depthHz, 0, 1000, 60);
        if (o.binary.trim() === "")
            o.binary = "aulactl";
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

        // MODULE SCHEMA: one typed property per persisted option, with its
        // default value. Never use `property var` here (Quickshell segfaults
        // deserializing objects); store maps as a JSON string and parse at
        // the reader.
        // When the overlay (and the feed) runs: "playing" (osu! map in
        // progress), "focused" (osu! window focused), "always", or "off".
        property string mode: "playing"
        // DOM key codes, comma or space separated, shown left to right.
        property string keys: "KeyZ,KeyX"
        // Screen corner: bottomRight, bottomLeft, bottomCenter, topRight,
        // topLeft, topCenter.
        property string corner: "bottomRight"
        property int marginPx: 24
        property int scalePercent: 100
        property int opacityPercent: 90
        // Key travel inside each keycap: "fill", "bar" (side bar) or "off".
        property string travelStyle: "fill"
        // Per-key press count under each keycap.
        property bool showCounts: true
        // KPS / peak / total line.
        property bool showStats: true
        // Current KPS beside the bar icon while the feed is live.
        property bool barShowKps: false
        // Seconds the overlay stays after osu! leaves the wanted state, so
        // a quick retry does not restart the feed.
        property int hideDelaySecs: 3
        // After a play: "results" keeps the overlay while osu!'s results
        // screen is open (then hideDelaySecs), "delay" only hideDelaySecs.
        property string keepAfterPlay: "results"
        // Zero the counters when the overlay appears or a new map starts.
        property bool resetOnSession: true
        // Bumped by the settings page's reset button; the value is ignored.
        property int resetRequest: 0
        // aulactl executable (name in PATH or absolute path).
        property string binary: "aulactl"
        // Pass --record --label=<beatmap> so every feed run is saved for
        // `aulactl replay report`.
        property bool record: true
        // --depth-hz for the feed; 0 keeps the feed's default.
        property int depthHz: 60
        // Output name (e.g. "eDP-1"); empty uses the first screen.
        property string monitor: ""
    }
}
