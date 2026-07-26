import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/network_traffic.json. Never touches the
 * shell's config.json.
 */
FileView {
    id: root
    // False until the file content (or its confirmed absence) is in the
    // adapter. Accounting must not initialise from default zeroes.
    property bool ready: false

    path: Directories.shellConfig + "/modules/network_traffic.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    // Materialise the merged adapter after every successful load. A config file
    // written by an older version is missing the keys added since, and the
    // adapter does not fall back to the defaults declared below for absent
    // keys — it yields the type zero value instead. Writing back on load keeps
    // upgrades honest and makes every option visible in the file.
    onLoaded: {
        writeAdapter()
        root.ready = true
    }
    onLoadFailed: error => {
        if (error == FileViewError.FileNotFound) {
            writeAdapter()
            root.ready = true
        }
    }

    property alias options: adapterItem
    adapter: JsonAdapter {
        id: adapterItem
        property int updateInterval: 2000
        property string excludeRegex: "^(lo|docker.*|veth.*|br-.*|virbr.*|tun.*|tap.*|wg.*|tailscale.*|CloudflareWARP)$"

        // Bar layout. "auto" picks stacked/horizontal from the screen width;
        // "stacked" and "horizontal" pin it.
        property string displayMode: "auto"
        // "auto" stacks at or below this screen width. The bar's right section
        // only gets whatever the centred middle section leaves over, which on a
        // 1920px screen with bar.verbose on is about 65px once the tray, the
        // indicator cluster and the weather pill have taken their share.
        property int autoStackMaxWidth: 1920
        // Direction arrows in stacked mode. Values are colour-coded either way
        // (download primary, upload tertiary); off saves another ~9px.
        property bool stackedShowIcons: true

        // Which totals the popup shows; left-click on the bar widget cycles it.
        property string statsPeriod: "boot" // "boot" | "today" | "month"

        // Per-app accounting (continuous nethogs/ss sampling). Off hides the
        // popup's app section and spawns nothing.
        property bool appMonitoring: true

        // Persisted accounting state (managed by TrafficLogic, flushed at most
        // once a minute — not user settings). rx/tx are bytes accumulated for
        // the key's period; sample* is the last /proc/net/dev reading so a
        // shell restart within one boot doesn't drop the interval since the
        // last flush, and a counter that shrank signals a reboot.
        property string acctDayKey: ""
        property real acctDayRx: 0
        property real acctDayTx: 0
        property string acctMonthKey: ""
        property real acctMonthRx: 0
        property real acctMonthTx: 0
        property real acctSampleRx: 0
        property real acctSampleTx: 0

        // Per-app accounting state (managed by AppTraffic, same flush cadence).
        // One record per app: n=name, dk/drx/dtx=day, mk/mrx/mtx=month,
        // brx/btx=boot. Boot buckets reset when appAcctBootId changes.
        property string appAcctBootId: ""
        property list<var> appAcct: []
    }
}
