.pragma library

// Do-not-disturb while playing: turns ii's Notifications.silent on while
// osu! is busy and gives the user's own setting back afterwards. Pure state
// machine; DndGuard.qml feeds it the osu! state and the current `silent`
// value and applies what it returns.
//
// Machine: { managing, saved, suspended }
//   managing   the module currently owns DND for this play
//   saved      the user's `silent` value from before the play
//   suspended  the user changed DND by hand during this play: leave it alone
//              until the next play starts

var MODES = ["playingCooldown", "playing", "off"];

function normalizeMode(mode) {
    return MODES.indexOf(mode) !== -1 ? mode : "playingCooldown";
}

// Whether DND is wanted for an osu-state value under the mode.
function wantDnd(mode, state) {
    switch (normalizeMode(mode)) {
    case "off":
        return false;
    case "playing":
        return state === "playing";
    default:
        return state === "playing" || state === "cooldown";
    }
}

function idle() {
    return { managing: false, saved: false, suspended: false };
}

// Start-up machine. `owed` is the persisted flag "this module turned DND on
// and still has to turn it off" (survives a module reload). If DND is still
// on, keep owning it; if it was reset (shell restart), start fresh.
function initial(owed, currentSilent) {
    if (owed === true && currentSilent === true)
        return { managing: true, saved: false, suspended: false };
    return idle();
}

// One step. Returns { machine, set, owed }: `set` is the value to write to
// Notifications.silent, or null to leave it; `owed` is the flag to persist.
function step(machine, want, currentSilent) {
    var m = machine || idle();
    var silent = currentSilent === true;
    var next;
    var set = null;
    if (m.managing) {
        if (!silent) {
            // Turned off by hand mid-play: stop managing, do not fight it.
            next = { managing: false, saved: m.saved, suspended: true };
        } else if (!want) {
            next = idle();
            if (m.saved !== silent)
                set = m.saved;
        } else {
            next = { managing: true, saved: m.saved, suspended: false };
        }
    } else if (!want) {
        // Play over: a suspension only lasts until the next play.
        next = idle();
    } else if (m.suspended) {
        next = { managing: false, saved: m.saved, suspended: true };
    } else {
        next = { managing: true, saved: silent, suspended: false };
        if (!silent)
            set = true;
    }
    return { machine: next, set: set, owed: next.managing && next.saved === false };
}
