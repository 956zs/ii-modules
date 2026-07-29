import QtQuick
import Quickshell.Io

/*
 * Sends one typed setting intent at a time to the primary bar instance. Values
 * are JSON argv entries, never shell text. A short bounded retry bridges owner
 * handoff and shell reloads without creating another config-file writer.
 */
Item {
    id: root

    property int maxAttempts: 8
    property var queue: []

    function send(key, value) {
        const next = root.queue.filter(request => request.key !== key)
        next.push({
            "key": key,
            "serializedValue": JSON.stringify(value),
            "attempts": 1
        });
        root.queue = next;
        root.pump();
    }

    function pump() {
        if (requestProc.running || retryTimer.running || root.queue.length === 0)
            return ;

        const next = root.queue.slice();
        requestProc.request = next.shift();
        root.queue = next;
        requestProc.running = true;
    }

    visible: false
    width: 0
    height: 0

    Timer {
        id: retryTimer

        interval: 150
        onTriggered: root.pump()
    }

    Process {
        id: requestProc

        property var request: null

        command: request === null ? [] : ["qs", "-c", "ii", "ipc", "--any-display", "call", "network_traffic", "setSetting", request.key, request.serializedValue]
        onExited: (exitCode, exitStatus) => {
            const request = requestProc.request;
            requestProc.request = null;
            if (exitCode !== 0 && request.attempts < root.maxAttempts) {
                request.attempts++;
                const next = root.queue.slice();
                next.unshift(request);
                root.queue = next;
                retryTimer.restart();
            } else {
                root.pump();
            }
        }
    }

}
