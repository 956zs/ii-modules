import Quickshell.Io
import qs.modules.common

/*
 * Per-module persisted options (IIMP convention): FileView + JsonAdapter on
 * ~/.config/illogical-impulse/modules/network-traffic.json. Never touches the
 * shell's config.json.
 */
FileView {
    id: root
    path: Directories.shellConfig + "/modules/network-traffic.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
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
    }
}
