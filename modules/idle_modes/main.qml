import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import qs.mod.idle_modes

/*
 * Owns the persisted idle mode. The Tier B patches add the mode to the stock
 * Idle service and make the "Keep awake" tile cycle it; this entry restores
 * the mode from modules/idle_modes.json on every shell start (including a
 * new Hyprland instance after a reboot) and writes every change back.
 */
Scope {
    id: root

    ConfigLoader {
        id: idleConfig
        owner: true
        onReadyChanged: {
            if (ready) {
                Idle.setIdleMode(idleConfig.options.mode);
                Idle.idleModesActive = true;
            }
        }
    }

    // Tile click, lock-screen "unlock and keep awake", or IPC -> file.
    Connections {
        target: Idle
        function onIdleModeChanged() {
            if (idleConfig.ready && idleConfig.options.mode !== Idle.idleMode)
                idleConfig.options.mode = Idle.idleMode;
        }
    }

    // The stock Idle service copies Persistent's inhibit flag once Persistent
    // has loaded; re-apply the mode afterwards so the two never disagree.
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready && Idle.idleModesActive)
                Idle.setIdleMode(Idle.idleMode);
        }
    }

    // Hand edits of the file -> shell.
    Connections {
        target: idleConfig.options
        function onModeChanged() {
            if (idleConfig.ready && Idle.idleMode !== idleConfig.options.mode)
                Idle.setIdleMode(idleConfig.options.mode);
        }
    }

    Component.onDestruction: Idle.idleModesActive = false
}
