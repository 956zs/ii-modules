import QtQuick
import qs.services
import "DndLogic.js" as Dnd

/*
 * Do not disturb while playing. Turns ii's Notifications.silent on while
 * the osu-state says osu! is busy, and restores the user's own value when
 * the play ends. A manual DND change during a play stops management until
 * the next play. Notifications are still stored, only their popups are
 * held back. Logic and edge cases: DndLogic.js.
 */
Item {
    id: root

    // ConfigLoader instance owned by main.qml (persists the owed flag).
    required property var config
    // "playingCooldown", "playing" or "off" (Dnd.normalizeMode).
    property string mode: "playingCooldown"
    property string osuState: "off"

    property var machine: Dnd.idle()
    property bool started: false

    function sync() {
        if (!root.started)
            return;
        const result = Dnd.step(root.machine, Dnd.wantDnd(root.mode, root.osuState), Notifications.silent);
        // Commit before writing: the write re-enters through onSilentChanged.
        root.machine = result.machine;
        if (root.config.options.dndOwed !== result.owed)
            root.config.options.dndOwed = result.owed;
        if (result.set !== null)
            Notifications.silent = result.set;
    }

    function start() {
        if (root.started || !root.config.ready)
            return;
        root.machine = Dnd.initial(root.config.options.dndOwed, Notifications.silent);
        root.started = true;
        root.sync();
    }

    onModeChanged: root.sync()
    onOsuStateChanged: root.sync()
    Component.onCompleted: root.start()

    Connections {
        target: root.config
        function onReadyChanged() {
            root.start();
        }
    }

    Connections {
        target: Notifications
        function onSilentChanged() {
            root.sync();
        }
    }

    // Disabled or reloaded mid-play: give DND back now; a reloaded instance
    // turns it on again on its first step if the play is still running.
    Component.onDestruction: {
        if (root.machine.managing && !root.machine.saved && Notifications.silent)
            Notifications.silent = false;
    }
}
