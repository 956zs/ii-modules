import QtQuick
import Quickshell.Io
import qs.modules.common
import "ConfigLogic.js" as ConfigLogic

/*
 * FileView + JsonAdapter persistence for network_traffic.json.
 * Adapter changes are field intents: reload the latest raw JSON, merge only
 * those fields, then atomically write it back. This keeps settings instances
 * writable without letting stale snapshots replace owner accounting or future
 * schema fields.
 */
FileView {
    id: root
    property bool ready: false
    property bool owner: false
    property bool ownerReady: false
    property bool materializing: true
    property bool acquiringOwner: false
    property bool internalReload: false
    property var pendingChanges: ({})
    signal relinquishing

    readonly property var defaults: ({
        updateInterval: 2000,
        excludeRegex: "^(lo|docker.*|veth.*|br-.*|virbr.*|tun.*|tap.*|wg.*|tailscale.*|CloudflareWARP)$",
        displayMode: "auto",
        autoStackMaxWidth: 1920,
        stackedShowIcons: true,
        statsPeriod: "today",
        statsPeriodSchema: 1,
        appMonitoring: true,
        pingHost: "auto",
        breatheThresholdKB: 1024,
        acctState: "",
        appAcctState: ""
    })

    path: Directories.shellConfig + "/modules/network_traffic.json"
    watchChanges: true
    blockAllReads: true
    blockWrites: true
    atomicWrites: true

    onFileChanged: {
        if (root.internalReload)
            return;
        root.materializing = true;
        reload();
    }

    onLoaded: {
        if (root.internalReload)
            return;
        const acquiring = root.acquiringOwner;
        root.acquiringOwner = false;
        const prepared = ConfigLogic.prepareConfig(text(), root.defaults, root.owner, 1);
        root.applyValues(prepared.values);
        if (prepared.shouldWrite)
            setText(prepared.serialized);
        root.ready = true;
        if (root.owner && (acquiring || !root.ownerReady))
            root.ownerReady = true;
    }

    onLoadFailed: error => {
        if (root.internalReload)
            return;
        if (error == FileViewError.FileNotFound) {
            root.applyValues(root.defaults);
            if (root.owner)
                setText(JSON.stringify(root.defaults));
            root.ready = true;
            root.ownerReady = root.owner;
            root.acquiringOwner = false;
        }
    }

    onOwnerChanged: {
        if (!root.owner) {
            ownerReload.stop();
            root.acquiringOwner = false;
            if (root.ownerReady)
                root.relinquishing();
            root.ownerReady = false;
            return;
        }
        if (!root.ready)
            return;
        root.ownerReady = false;
        root.acquiringOwner = true;
        ownerReload.restart();
    }

    property var ownerReload: Timer {
        interval: 100
        onTriggered: {
            if (!root.owner)
                return;
            root.materializing = true;
            root.reload();
        }
    }

    function applyValues(values) {
        root.materializing = true;
        adapterItem.updateInterval = values.updateInterval;
        adapterItem.excludeRegex = values.excludeRegex;
        adapterItem.displayMode = values.displayMode;
        adapterItem.autoStackMaxWidth = values.autoStackMaxWidth;
        adapterItem.stackedShowIcons = values.stackedShowIcons;
        adapterItem.statsPeriod = values.statsPeriod;
        adapterItem.statsPeriodSchema = values.statsPeriodSchema;
        adapterItem.appMonitoring = values.appMonitoring;
        adapterItem.pingHost = values.pingHost;
        adapterItem.breatheThresholdKB = values.breatheThresholdKB;
        adapterItem.acctState = values.acctState;
        adapterItem.appAcctState = values.appAcctState;
        root.materializing = false;
    }

    function queueChange(key, value) {
        if (!root.ready || root.materializing)
            return;
        const changes = Object.assign({}, root.pendingChanges);
        changes[key] = value;
        root.pendingChanges = changes;
        root.flushPendingChanges();
    }

    function flushPendingChanges() {
        const changes = root.pendingChanges;
        root.pendingChanges = {};
        root.materializing = true;
        root.internalReload = true;
        root.reload();
        const latest = root.text();
        root.internalReload = false;
        const merged = ConfigLogic.mergeConfigChanges(
            latest, changes, root.owner || root.ownerReady);
        if (merged.changed)
            root.setText(merged.serialized);
        const prepared = ConfigLogic.prepareConfig(merged.serialized, root.defaults, false, 1);
        root.applyValues(prepared.values);
    }

    property alias options: adapterItem
    adapter: JsonAdapter {
        id: adapterItem
        property int updateInterval: 2000
        onUpdateIntervalChanged: root.queueChange("updateInterval", updateInterval)
        property string excludeRegex: "^(lo|docker.*|veth.*|br-.*|virbr.*|tun.*|tap.*|wg.*|tailscale.*|CloudflareWARP)$"
        onExcludeRegexChanged: root.queueChange("excludeRegex", excludeRegex)
        property string displayMode: "auto"
        onDisplayModeChanged: root.queueChange("displayMode", displayMode)
        property int autoStackMaxWidth: 1920
        onAutoStackMaxWidthChanged: root.queueChange("autoStackMaxWidth", autoStackMaxWidth)
        property bool stackedShowIcons: true
        onStackedShowIconsChanged: root.queueChange("stackedShowIcons", stackedShowIcons)
        property string statsPeriod: "today"
        onStatsPeriodChanged: root.queueChange("statsPeriod", statsPeriod)
        property int statsPeriodSchema: 1
        onStatsPeriodSchemaChanged: root.queueChange("statsPeriodSchema", statsPeriodSchema)
        property bool appMonitoring: true
        onAppMonitoringChanged: root.queueChange("appMonitoring", appMonitoring)
        property string pingHost: "auto"
        onPingHostChanged: root.queueChange("pingHost", pingHost)
        property int breatheThresholdKB: 1024
        onBreatheThresholdKBChanged: root.queueChange("breatheThresholdKB", breatheThresholdKB)
        property string acctState: ""
        onAcctStateChanged: root.queueChange("acctState", acctState)
        property string appAcctState: ""
        onAppAcctStateChanged: root.queueChange("appAcctState", appAcctState)
    }
}
