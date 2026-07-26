import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/network_traffic.json. Never touches the
 * shell's config.json.
 */
FileView {
    id: root
    path: Directories.shellConfig + "/modules/network_traffic.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    // Materialise the merged adapter after every successful load. A config file
    // written by an older version is missing the keys added since, and the
    // adapter does not fall back to the defaults declared below for absent
    // keys — it yields the type zero value instead. Writing back on load keeps
    // upgrades honest and makes every option visible in the file.
    onLoaded: writeAdapter()
    onLoadFailed: error => {
        if (error == FileViewError.FileNotFound) {
            writeAdapter()
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
        // Direction arrows in stacked mode. Off trades them for colour coding
        // (download primary, upload tertiary) and saves another ~9px.
        property bool stackedShowIcons: true
    }
}
