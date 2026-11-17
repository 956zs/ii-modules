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

    path: Directories.shellConfig + "/modules/androlink_status.json"
    watchChanges: true
    blockWrites: true
    atomicWrites: true

    function clamp(value, low, high, fallback) {
        const n = Math.round(Number(value));
        return Number.isFinite(n) ? Math.min(high, Math.max(low, n)) : fallback;
    }

    onFileChanged: {
        root.materializing = true;
        reload();
    }
    onAdapterUpdated: {
        if (!root.materializing)
            writeAdapter();
    }
    onLoaded: {
        // MODULE VALIDATION: heal out-of-range numbers to the nearest sane value.
        adapterItem.lowBatteryThreshold = root.clamp(adapterItem.lowBatteryThreshold, 1, 95, 20);
        adapterItem.rearmMargin = root.clamp(adapterItem.rearmMargin, 1, 50, 5);
        adapterItem.heartbeatSecs = root.clamp(adapterItem.heartbeatSecs, 5, 3600, 30);
        adapterItem.pollSecs = root.clamp(adapterItem.pollSecs, 2, 300, 10);
        adapterItem.actionTimeoutSecs = root.clamp(adapterItem.actionTimeoutSecs, 3, 120, 15);
        adapterItem.reminderMinIntervalMins = root.clamp(adapterItem.reminderMinIntervalMins, 0, 1440, 30);
        adapterItem.refreshMinIntervalSecs = root.clamp(adapterItem.refreshMinIntervalSecs, 0, 300, 10);
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
        // Keep a quiet "not running" capsule instead of hiding it.
        property bool showWhenNotRunning: false
        // Unread-notification count beside the battery.
        property bool showUnread: true
        // One desktop notification per discharge cycle when the phone runs low.
        property bool lowBatteryReminder: true
        // Battery percent at or below which the reminder fires.
        property int lowBatteryThreshold: 20
        // Points above the threshold the level must climb to re-arm.
        property int rearmMargin: 5
        // androlink's status heartbeat; three missed beats = stale.
        property int heartbeatSecs: 30
        // Fallback re-read of the status file, in seconds.
        property int pollSecs: 10
        // A panel action still running after this many seconds is stopped.
        property int actionTimeoutSecs: 15
        // Least time between two reminders for the same phone (0 = no limit).
        property int reminderMinIntervalMins: 30
        // Least seconds between two Reconnect runs from the panel (0 = no
        // limit here; androlink applies its own limit too).
        property int refreshMinIntervalSecs: 10
        // Reminder state written by the window slot (StatusLogic
        // serializeReminderState): which phones are armed and when each was
        // last reminded. A JSON string, never a var (see MODULE SCHEMA).
        property string reminderState: ""
    }
}
