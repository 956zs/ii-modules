import "ConfigLogic.js" as ConfigLogic
import QtQuick
import Quickshell.Io
import qs.modules.common

/*
 * FileView + JsonAdapter persistence for network_traffic.json.
 * Every instance watches and materializes values, but only the elected owner
 * may turn adapter changes into writes. Settings and secondary bars send typed
 * intents over IPC to that owner, keeping accounting and options serialized in
 * one process.
 */
FileView {
    id: root

    property bool ready: false
    property bool owner: false
    property bool ownerReady: false
    property bool materializing: true
    property bool acquiringOwner: false
    property bool internalReload: false
    property var pendingChanges: ({
    })
    readonly property var defaults: ({
        "updateInterval": 2000,
        "excludeRegex": "^(lo|docker.*|veth.*|br-.*|virbr.*|tun.*|tap.*|wg.*|tailscale.*|CloudflareWARP)$",
        "displayMode": "auto",
        "autoStackMaxWidth": 1920,
        "stackedShowIcons": true,
        "statsPeriod": "today",
        "statsPeriodSchema": 1,
        "appMonitoring": true,
        "pingHost": "auto",
        "breatheThresholdKB": 1024,
        "acctState": "",
        "appAcctState": ""
    })
    property var ownerReload

    ownerReload: Timer {
        interval: 100
        onTriggered: {
            if (!root.owner)
                return ;

            root.materializing = true;
            root.reload();
        }
    }

    property alias options: adapterItem

    signal relinquishing()

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
        if (!root.ready || root.materializing || !root.ownerReady)
            return ;

        const changes = Object.assign({
        }, root.pendingChanges);
        changes[key] = value;
        root.pendingChanges = changes;
        root.flushPendingChanges();
    }

    function requestSerializedSetting(key, serializedValue) {
        const intent = ConfigLogic.decodeSettingIntent(key, serializedValue);
        if (!root.ownerReady || !intent.accepted)
            return false;

        root.queueChange(intent.key, intent.value);
        return true;
    }

    function flushPendingChanges() {
        const changes = root.pendingChanges;
        root.pendingChanges = {
        };
        root.materializing = true;
        root.internalReload = true;
        root.reload();
        const latest = root.text();
        root.internalReload = false;
        const merged = ConfigLogic.mergeConfigChanges(latest, changes, root.owner || root.ownerReady);
        if (merged.changed)
            root.setText(merged.serialized);

        const prepared = ConfigLogic.prepareConfig(merged.serialized, root.defaults, false, 1);
        root.applyValues(prepared.values);
    }

    path: Directories.shellConfig + "/modules/network_traffic.json"
    watchChanges: true
    blockAllReads: true
    blockWrites: true
    atomicWrites: true
    onFileChanged: {
        if (root.internalReload)
            return ;

        root.materializing = true;
        reload();
    }
    onLoaded: {
        if (root.internalReload)
            return ;

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
    onLoadFailed: (error) => {
        if (root.internalReload)
            return ;

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
            return ;
        }
        if (!root.ready)
            return ;

        root.ownerReady = false;
        root.acquiringOwner = true;
        ownerReload.restart();
    }

    adapter: JsonAdapter {
        id: adapterItem

        property int updateInterval: 2000
        property string excludeRegex: "^(lo|docker.*|veth.*|br-.*|virbr.*|tun.*|tap.*|wg.*|tailscale.*|CloudflareWARP)$"
        property string displayMode: "auto"
        property int autoStackMaxWidth: 1920
        property bool stackedShowIcons: true
        property string statsPeriod: "today"
        property int statsPeriodSchema: 1
        property bool appMonitoring: true
        property string pingHost: "auto"
        property int breatheThresholdKB: 1024
        property string acctState: ""
        property string appAcctState: ""

        onUpdateIntervalChanged: root.queueChange("updateInterval", updateInterval)
        onExcludeRegexChanged: root.queueChange("excludeRegex", excludeRegex)
        onDisplayModeChanged: root.queueChange("displayMode", displayMode)
        onAutoStackMaxWidthChanged: root.queueChange("autoStackMaxWidth", autoStackMaxWidth)
        onStackedShowIconsChanged: root.queueChange("stackedShowIcons", stackedShowIcons)
        onStatsPeriodChanged: root.queueChange("statsPeriod", statsPeriod)
        onStatsPeriodSchemaChanged: root.queueChange("statsPeriodSchema", statsPeriodSchema)
        onAppMonitoringChanged: root.queueChange("appMonitoring", appMonitoring)
        onPingHostChanged: root.queueChange("pingHost", pingHost)
        onBreatheThresholdKBChanged: root.queueChange("breatheThresholdKB", breatheThresholdKB)
        onAcctStateChanged: root.queueChange("acctState", acctState)
        onAppAcctStateChanged: root.queueChange("appAcctState", appAcctState)
    }

}
