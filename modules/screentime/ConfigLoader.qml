// Vendored from lib/ConfigLoader.template.qml (golden master; see
// lib/README.md in the ii-modules repository). Each module ships its own
// copy — IIMP modules are self-contained and never import another module's
// files. Keep the skeleton invariants; tools/lib-sync/check-configloader.mjs
// verifies every first-party copy.
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
 * atomicWrites additionally makes each blob write temp+rename, so a crash
 * mid-write can never leave a truncated history file behind.
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
    // Guards the reload/write echo: adapter updates during materialization
    // must not be written back, or every reload triggers a write loop.
    property bool materializing: true

    path: Directories.shellConfig + "/modules/screentime.json"
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
    // Materialise the merged adapter after every successful load: a config
    // file written by an older version misses keys added since, and the
    // adapter yields type zero values for absent keys, not the declared
    // defaults. Writing back on load keeps upgrades honest.
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

        // Comma-separated appId/class substrings that are never accounted
        // (matched case-insensitively).
        property string excludedApps: ""

        // A wall-clock jump larger than this between accounting events is
        // treated as suspend/AFK and credited to nothing.
        property int idleGapSec: 90

        // Keep the 30-day daily history. Off wipes and stops recording
        // anything older than today.
        property bool keepHistory: true

        // AI agent work time: samples /proc every 10s for processes whose
        // comm matches this regex; a session counts as "working" in a window
        // where its process tree burned more CPU than the threshold below.
        // Keeps counting while the screen is locked — an agent working while
        // you are away is exactly what this dimension measures.
        property bool aiTracking: true
        property string aiProcessRegex: "^(claude|codex)$"

        // Working threshold, percent of one core over the sample window.
        // Calibrated on real sessions: a claude CLI idle at its prompt is
        // 0%, a working one 20%+, so 1% separates them with margin.
        property int aiActiveCpuPct: 1

        // Usage history blob, managed by ScreentimeLogic in the window slot,
        // flushed at most once a minute — not a user setting.
        // {v, day:{k,apps:{id:sec},hours:[24],hoursComplete:bool},
        //  days:[{k,total,apps:[{n,s}],hours?:[24],aiU,aiS,aiP}]}
        // Historical `hours` is optional: records written before v1.3 keep
        // their daily totals but are excluded from hourly heatmap coverage.
        // `hoursComplete` prevents a mid-day upgrade from presenting the
        // post-upgrade tail as a complete day's hourly distribution.
        // NEVER a `property var` — Quickshell's deserializer segfaults
        // writing a JSON object into one. JSON string + parse at the reader.
        property string histState: ""
    }
}
