import QtQuick
import Quickshell.Io
import qs.modules.common

/*
 * Multi-adapter network backend (instance, not a singleton — IIMP modules
 * pass instances down). Talks to NetworkManager exclusively through nmcli,
 * parsing its `-t` (terse) output ourselves: no stock Network service is
 * involved for WifiPanel's content, so every wifi adapter, the bluetooth-
 * tethered (PAN/NAP) connection profiles, and ethernet all get first-class
 * treatment instead of stock's single-active-device view.
 *
 * All nmcli calls go through one Process (command swapped between jobs) fed
 * by a small in-memory queue, so a refresh cycle — radio state, device
 * status, bluetooth connection profiles, then one wifi-list per adapter —
 * never spawns more than one child at a time.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool wifiRadioEnabled: true
    property bool busy: false
    property string lastError: ""
    // Bumped whenever sections (or radio state) change, for bindings that
    // want an explicit revision to key off rather than deep-watching lists.
    property int revision: 0
    // [{kind:"wifi", iface, state, connection, networks:[...]},
    //  {kind:"bluetooth", connections:[...], devices:[...]},
    //  {kind:"ethernet", iface, state, connection}]
    property list<var> sections: []

    // --- nmcli terse-format helpers ----------------------------------------
    // Fields are colon-separated with backslash-escaped colons inside values
    // (MAC addresses, SSIDs, connection names can all contain them).

    function splitNmcli(line) {
        const fields = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) {
                cur += line[i + 1]
                i++
            } else if (c === ":") {
                fields.push(cur)
                cur = ""
            } else {
                cur += c
            }
        }
        fields.push(cur)
        return fields
    }

    function parseDeviceStatus(text) {
        const wifi = [], bt = [], eth = []
        const skipTypes = ["loopback", "bridge", "tun", "wifi-p2p"]
        for (const line of text.split("\n")) {
            if (line.trim() === "") continue
            const f = root.splitNmcli(line)
            if (f.length < 4) continue
            const device = f[0], type = f[1], state = f[2], connection = f[3]
            if (skipTypes.includes(type)) continue
            if (type === "wifi") wifi.push({ iface: device, state, connection })
            else if (type === "bt") bt.push({ mac: device, state })
            else if (type === "ethernet") eth.push({ iface: device, state, connection })
        }
        return { wifi, bt, eth }
    }

    function parseBtConnections(text) {
        const conns = []
        for (const line of text.split("\n")) {
            if (line.trim() === "") continue
            const f = root.splitNmcli(line)
            if (f.length < 3) continue
            const name = f[0], type = f[1], device = f[2]
            if (type === "bluetooth") conns.push({ name, device })
        }
        return conns
    }

    // SSIDs repeat across BSSIDs — dedupe per adapter, keeping the in-use row
    // first and otherwise the strongest signal.
    function parseWifiList(text) {
        const bySsid = ({})
        const order = []
        for (const line of text.split("\n")) {
            if (line.trim() === "") continue
            const f = root.splitNmcli(line)
            if (f.length < 4) continue
            const inUse = f[0] === "*"
            const ssid = f[1]
            const signal = parseInt(f[2]) || 0
            const security = f[3]
            if (ssid === "") continue // hidden network: nothing to key or connect on
            const existing = bySsid[ssid]
            if (!existing) {
                order.push(ssid)
                bySsid[ssid] = { ssid, inUse, signal, security }
            } else if ((inUse && !existing.inUse) || (!existing.inUse && signal > existing.signal)) {
                bySsid[ssid] = { ssid, inUse, signal, security }
            }
        }
        return order.map(s => bySsid[s]).sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal))
    }

    // --- process queue -------------------------------------------------------

    property var _queue: []
    property bool _running: false

    function _enqueue(cmd, done) {
        root._queue.push({ cmd, done })
        root.busy = true
        root._pump()
    }

    function _pump() {
        if (root._running || root._queue.length === 0) return
        root._running = true
        const job = root._queue.shift()
        proc._done = job.done
        proc.command = job.cmd
        proc.running = true
    }

    Process {
        id: proc
        property var _done: null
        stdout: StdioCollector { id: procStdout }
        stderr: StdioCollector { id: procStderr }
        onExited: (exitCode, exitStatus) => {
            const done = proc._done
            proc._done = null
            root._running = false
            if (root._queue.length === 0) root.busy = false
            if (done) done(exitCode, procStdout.text, procStderr.text)
            root._pump()
        }
    }

    // --- refresh pipeline ------------------------------------------------
    // radio state -> device status -> bt connection profiles -> per-adapter
    // wifi list (sequential, skipped entirely while the radio is off).

    property var _scanRemaining: []
    property var _scanResults: ({})
    property var _pendingParsed: null

    function refresh() {
        root._enqueue(["nmcli", "-t", "-f", "WIFI", "radio", "wifi"], (code, out) => {
            root.wifiRadioEnabled = out.trim() === "enabled"
            root._enqueue(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"], (code2, out2) => {
                root._pendingParsed = root.parseDeviceStatus(out2)
                root._enqueue(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show"], (code3, out3) => {
                    root._pendingParsed.btConns = root.parseBtConnections(out3)
                    root._scanRemaining = root.wifiRadioEnabled ? root._pendingParsed.wifi.slice() : []
                    root._scanResults = ({})
                    root._scanNext()
                })
            })
        })
    }

    function _scanNext() {
        if (root._scanRemaining.length === 0) {
            root._commitSections()
            return
        }
        const dev = root._scanRemaining.shift()
        root._enqueue(["nmcli", "-t", "-e", "yes", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "ifname", dev.iface], (code, out) => {
            root._scanResults[dev.iface] = root.parseWifiList(out)
            root._scanNext()
        })
    }

    function _commitSections() {
        const p = root._pendingParsed
        const sections = []
        for (const w of p.wifi) {
            sections.push({
                kind: "wifi",
                iface: w.iface,
                state: w.state,
                connection: w.connection,
                networks: root._scanResults[w.iface] ?? []
            })
        }
        if (p.btConns.length > 0 || p.bt.length > 0) {
            sections.push({ kind: "bluetooth", connections: p.btConns, devices: p.bt })
        }
        for (const e of p.eth) {
            if (e.state !== "unavailable") {
                sections.push({ kind: "ethernet", iface: e.iface, state: e.state, connection: e.connection })
            }
        }
        root.sections = sections
        root._pendingParsed = null
        root.revision++
    }

    // --- actions -----------------------------------------------------------

    function toggleWifiRadio() {
        root.lastError = ""
        root._enqueue(["nmcli", "radio", "wifi", root.wifiRadioEnabled ? "off" : "on"], () => root.refresh())
    }

    function rescan(iface) {
        root.lastError = ""
        const cmd = iface ? ["nmcli", "dev", "wifi", "rescan", "ifname", iface] : ["nmcli", "dev", "wifi", "rescan"]
        root._enqueue(cmd, () => root.refresh())
    }

    function connectWifi(iface, ssid, password) {
        root.lastError = ""
        const cmd = (password && password.length > 0)
            ? ["nmcli", "dev", "wifi", "connect", ssid, "ifname", iface, "password", password]
            : ["nmcli", "dev", "wifi", "connect", ssid, "ifname", iface]
        root._enqueue(cmd, (code, out, err) => {
            if (code !== 0) {
                root.lastError = (err && err.trim()) || (out && out.trim()) || Translation.tr("Connection failed")
            }
            root.refresh()
        })
    }

    function disconnectDevice(iface) {
        root.lastError = ""
        root._enqueue(["nmcli", "device", "disconnect", iface], () => root.refresh())
    }

    function connectDevice(iface) {
        root.lastError = ""
        root._enqueue(["nmcli", "device", "connect", iface], () => root.refresh())
    }

    function upConnection(name) {
        root.lastError = ""
        root._enqueue(["nmcli", "connection", "up", name], () => root.refresh())
    }

    function downConnection(name) {
        root.lastError = ""
        root._enqueue(["nmcli", "connection", "down", name], () => root.refresh())
    }
}
