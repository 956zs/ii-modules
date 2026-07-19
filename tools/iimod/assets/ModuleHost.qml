// IIMP module host — installed and owned by iimod. DO NOT EDIT (recomposed on reapply).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Scope {
    id: root
    property var instances: ({})

    function sync() {
        const want = Config.ready ? (Config.options.iimp?.enabledWindow ?? []) : [];
        for (const id in instances) {
            if (!want.includes(id)) {
                instances[id]?.destroy();
                delete instances[id];
            }
        }
        for (const id of want) {
            if (id in instances || !/^[a-z][a-z0-9-]{1,30}$/.test(id))
                continue;
            instances[id] = null; // in-flight marker
            const comp = Qt.createComponent(Quickshell.shellPath(`mod/${id}/main.qml`), Component.Asynchronous);
            const finish = () => {
                if (comp.status === Component.Ready) {
                    const obj = comp.createObject(root);
                    if (obj) {
                        instances[id] = obj;
                    } else {
                        console.warn(`[iimp] createObject failed: ${id}`);
                        delete instances[id];
                    }
                } else if (comp.status === Component.Error) {
                    console.warn(`[iimp] window module failed: ${id}: ${comp.errorString()}`);
                    delete instances[id];
                }
            };
            if (comp.status === Component.Loading)
                comp.statusChanged.connect(finish);
            else
                finish();
        }
    }

    Connections {
        target: Config.options.iimp ?? null
        function onEnabledWindowChanged() { root.sync() }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.sync() }
    }
    Component.onCompleted: root.sync()

    IpcHandler {
        target: "iimp"
        function ping(): string { return "pong" }
        function reload(): void { Quickshell.reload(true) }
        function setEnabled(id: string, slot: string, on: bool): void {
            const key = slot === "bar" ? "enabledBar" : "enabledWindow";
            const cur = [...(Config.options.iimp[key] ?? [])];
            const i = cur.indexOf(id);
            if (on && i < 0) cur.push(id);
            else if (!on && i >= 0) cur.splice(i, 1);
            else return;
            Config.options.iimp[key] = cur.sort();
        }
    }
}
