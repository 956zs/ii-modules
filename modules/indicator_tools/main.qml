import Quickshell
import Quickshell.Io
import qs.mod.indicator_tools

/*
 * Window-slot entry: hosts the WiFi/Bluetooth panels and the IPC surface the
 * Tier B patches call into (right-click on the stock indicator icons runs
 * `qs -c ii ipc call indicator_tools toggleWifi|toggleBt`).
 */
Scope {
    id: root

    WifiPanel { id: wifiPanel }
    BtPanel { id: btPanel }

    IpcHandler {
        target: "indicator_tools"

        function toggleWifi(): void {
            btPanel.visible = false;
            wifiPanel.toggle();
        }

        function toggleBt(): void {
            wifiPanel.visible = false;
            btPanel.toggle();
        }
    }
}
