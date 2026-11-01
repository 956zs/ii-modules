import QtQuick
import Quickshell
import qs.mod.osu_indicator
import "DndLogic.js" as Dnd

/*
 * Window-slot entry, loaded once (bar entries exist per monitor): owns the
 * config file and the do-not-disturb guard, which must act exactly once.
 */
Scope {
    id: root

    ConfigLoader {
        id: cfg
        owner: true
    }

    OsuState {
        id: osuReader
        // Only the state is used here; no timer text, so no 1 s ticker.
        showTimer: false
        active: Dnd.normalizeMode(cfg.options.dndMode) !== "off"
    }

    DndGuard {
        config: cfg
        mode: Dnd.normalizeMode(cfg.options.dndMode)
        osuState: osuReader.state
    }
}
