import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/network_traffic.json. Never touches the
 * shell's config.json.
 *
 * Accounting state lives in two JSON-string blobs (acctState/appAcctState),
 * each updated by a single adapter assignment. Per-field storage proved
 * unsafe: every assignment rewrites the whole file, watchChanges reloads race
 * with our own writes, and iimod's hot reload briefly runs old and new
 * instances side by side — a multi-field flush could be read back as a torn
 * snapshot (fresh day counters, stale month counters), which is how "this
 * month < today" happened. One assignment per blob makes a torn read
 * structurally impossible.
 */
FileView {
    id: root
    // False until the file content (or its confirmed absence) is in the
    // adapter. Accounting must not initialise from default zeroes.
    property bool ready: false
    // Exactly one instance (the bar widget's) materialises defaults and
    // migrations into the file. Read-only consumers like the settings
    // fragment must not write stale snapshots over the owner's state.
    property bool owner: false

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
        migrateLegacyAccounting()
        if (root.owner) writeAdapter()
        root.ready = true
    }
    onLoadFailed: error => {
        if (error == FileViewError.FileNotFound) {
            if (root.owner) writeAdapter()
            root.ready = true
        }
    }

    // 1.2.0/1.3.0 stored accounting as separate acct* fields; fold them into
    // the blobs before the owner's writeAdapter erases unknown keys. Repairs
    // torn legacy state on the way: a month contains its days.
    function migrateLegacyAccounting() {
        if (adapterItem.acctState !== "") return
        let j = null
        try {
            j = JSON.parse(text())
        } catch (e) {
            return
        }
        if (!j || typeof j !== "object") return
        if (j.acctDayKey !== undefined) {
            const st = {
                v: 1,
                day: { k: j.acctDayKey ?? "", rx: j.acctDayRx ?? 0, tx: j.acctDayTx ?? 0 },
                month: { k: j.acctMonthKey ?? "", rx: j.acctMonthRx ?? 0, tx: j.acctMonthTx ?? 0 },
                sample: { rx: j.acctSampleRx ?? 0, tx: j.acctSampleTx ?? 0 }
            }
            if (st.month.k !== "" && st.day.k.startsWith(st.month.k)) {
                st.month.rx = Math.max(st.month.rx, st.day.rx)
                st.month.tx = Math.max(st.month.tx, st.day.tx)
            }
            adapterItem.acctState = JSON.stringify(st)
        }
        if (adapterItem.appAcctState === "" && j.appAcct !== undefined) {
            adapterItem.appAcctState = JSON.stringify({
                v: 1,
                bootId: j.appAcctBootId ?? "",
                apps: j.appAcct ?? []
            })
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

        // Ping target for the popup's latency row. "auto" resolves the host's
        // configured DNS (resolvectl/resolv.conf; loopback stubs and the
        // tailscale magic resolver skipped, public addresses preferred).
        // Any hostname or IP pins it.
        property string pingHost: "auto"

        // Bar arrows breathe while that direction's rate is at or above this
        // (KiB/s).
        property int breatheThresholdKB: 1024

        // Whole-system accounting blob, managed by TrafficLogic, flushed at
        // most once a minute — not a user setting.
        // {v, day:{k,rx,tx}, month:{k,rx,tx}, sample:{rx,tx}}
        property string acctState: ""
        // Per-app accounting blob, managed by AppTraffic, same cadence.
        // {v, bootId, apps:[{n,dk,drx,dtx,mk,mrx,mtx,brx,btx}]}
        property string appAcctState: ""
    }
}
