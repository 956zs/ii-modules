import QtQuick
import Quickshell
import Quickshell.Io
import qs.mod.aula_keys
import "AulaKeysLogic.js" as Logic

/*
 * Window-slot entry, loaded once: owns the config file, the osu! state
 * reader, the visibility state machine, the feed process and the overlay.
 * The feed runs exactly while the overlay is shown, because it holds the
 * keyboard's device lock. IPC: `qs -c ii ipc call aula_keys reset|status`.
 */
Scope {
    id: root

    ConfigLoader {
        id: cfg
        owner: true
    }

    readonly property string mode: Logic.normalizeMode(cfg.options.mode)
    readonly property var keyList: Logic.parseKeyList(cfg.options.keys)

    OsuWatch {
        id: osuWatch
        active: cfg.ready && root.mode !== "off"
    }

    // Visibility machine (Logic.stepVisibility): shows at once, hides after
    // the configured linger.
    property var machine: ({ visible: false, hideAt: 0 })
    readonly property bool shown: machine.visible
    readonly property bool wanted: cfg.ready && Logic.wantVisible(root.mode, osuWatch.state)

    function step() {
        const next = Logic.stepVisibility(root.machine, root.wanted, Date.now(), cfg.options.hideDelaySecs * 1000);
        if (next.visible !== root.machine.visible || next.hideAt !== root.machine.hideAt)
            root.machine = next;
        if (next.hideAt > 0) {
            lingerTimer.interval = Math.max(1, next.hideAt - Date.now());
            lingerTimer.restart();
        } else {
            lingerTimer.stop();
        }
    }

    onWantedChanged: root.step()
    onShownChanged: {
        if (root.shown && cfg.options.resetOnSession)
            keyFeed.resetCounts();
    }

    Timer {
        id: lingerTimer
        repeat: false
        onTriggered: root.step()
    }

    // A new map (playing with a new start time) is a new session as well.
    property int lastPlaySince: 0
    Connections {
        target: osuWatch
        function onRecordChanged() {
            if (osuWatch.state !== "playing" || osuWatch.since === root.lastPlaySince)
                return;
            root.lastPlaySince = osuWatch.since;
            if (root.shown && cfg.options.resetOnSession)
                keyFeed.resetCounts();
        }
    }

    // Reset button in the settings page bumps resetRequest in the file.
    property int seenResetRequest: -1
    Connections {
        target: cfg
        function onReadyChanged() {
            root.seenResetRequest = cfg.options.resetRequest;
        }
    }
    Connections {
        target: cfg.options
        function onResetRequestChanged() {
            if (!cfg.ready || cfg.options.resetRequest === root.seenResetRequest)
                return;
            root.seenResetRequest = cfg.options.resetRequest;
            keyFeed.resetCounts();
        }
    }

    KeyFeed {
        id: keyFeed
        active: root.shown
        binary: cfg.options.binary
        keys: root.keyList
        depthHz: cfg.options.depthHz
    }

    LazyLoader {
        active: root.shown

        KeyOverlay {
            feed: keyFeed
            screen: {
                const name = cfg.options.monitor;
                const match = Quickshell.screens.find(s => s.name === name);
                return match ?? Quickshell.screens[0] ?? null;
            }
            corner: Logic.normalizeCorner(cfg.options.corner)
            marginPx: cfg.options.marginPx
            uiScale: cfg.options.scalePercent / 100
            contentOpacity: cfg.options.opacityPercent / 100
            showCounts: cfg.options.showCounts
            showStats: cfg.options.showStats
        }
    }

    IpcHandler {
        target: "aula_keys"

        function reset(): void {
            keyFeed.resetCounts();
        }

        function status(): string {
            return JSON.stringify({
                mode: root.mode,
                osu: osuWatch.state,
                shown: root.shown,
                feed: !root.shown ? "stopped" : keyFeed.status === "" ? "live" : keyFeed.status,
                total: keyFeed.total,
                peak: keyFeed.peak
            });
        }
    }
}
