.pragma library

// Pure helpers for the osu! play-state indicator. The daemon (osu-state)
// publishes $XDG_RUNTIME_DIR/osu-state.json; this file turns its text into a
// safe record and formats what the bar and popup display.

var STATES = ["off", "idle", "menu", "playing", "cooldown"];

function finite(value, fallback) {
    var n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

// Record for a missing, malformed, or foreign file: the game is "off".
function offState() {
    return { state: "off", since: 0, beatmap: "", cooldownUntil: 0, valid: false };
}

// Parses the state file text. Anything not matching the daemon's contract
// collapses to `off` so a corrupt file can never show a stale "playing".
function parseState(text) {
    if (typeof text !== "string" || text.trim() === "")
        return offState();
    var data;
    try {
        data = JSON.parse(text);
    } catch (error) {
        return offState();
    }
    if (!data || typeof data !== "object" || STATES.indexOf(data.state) === -1)
        return offState();
    var beatmap = typeof data.beatmap === "string" ? data.beatmap.trim() : "";
    return {
        state: data.state,
        since: Math.max(0, Math.floor(finite(data.since, 0))),
        beatmap: beatmap,
        cooldownUntil: data.state === "cooldown" ? Math.max(0, Math.floor(finite(data.cooldown_until, 0))) : 0,
        valid: true
    };
}

// Whether the bar pill is shown for `state` under the user's switches.
function shownFor(state, showIdle, showMenu) {
    switch (state) {
    case "playing":
    case "cooldown":
        return true;
    case "idle":
        return showIdle !== false;
    case "menu":
        return showMenu !== false;
    default:
        return false;
    }
}

// Seconds the current state has lasted, never negative.
function elapsed(record, nowSecs) {
    if (!record || !record.since)
        return 0;
    return Math.max(0, Math.floor(finite(nowSecs, 0) - record.since));
}

// Seconds left in the cooldown, 0 outside it.
function cooldownLeft(record, nowSecs) {
    if (!record || record.state !== "cooldown" || !record.cooldownUntil)
        return 0;
    return Math.max(0, Math.ceil(record.cooldownUntil - finite(nowSecs, 0)));
}

// "m:ss", or "h:mm:ss" past an hour.
function formatDuration(secs) {
    var total = Math.max(0, Math.floor(finite(secs, 0)));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var mm = h > 0 && m < 10 ? "0" + m : String(m);
    var ss = s < 10 ? "0" + s : String(s);
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
}

// Text beside the icon: elapsed play time, or the cooldown countdown.
function barText(record, nowSecs, showTimer) {
    if (!record || showTimer === false)
        return "";
    if (record.state === "playing")
        return formatDuration(elapsed(record, nowSecs));
    if (record.state === "cooldown")
        return formatDuration(cooldownLeft(record, nowSecs));
    return "";
}

// Whether the 1 s ticker is needed (something on screen counts).
function needsTicker(record, showTimer) {
    return !!record && showTimer !== false && (record.state === "playing" || record.state === "cooldown");
}

// Splits "Artist - Title (mapper) [Diff]" for the popup; falls back to the
// raw string when the shape differs.
function splitBeatmap(beatmap) {
    var raw = typeof beatmap === "string" ? beatmap.trim() : "";
    if (raw === "")
        return { title: "", mapper: "", difficulty: "" };
    var match = /^(.*?)\s*\(([^()]*)\)\s*\[([^\]]*)\]\s*$/.exec(raw);
    if (!match)
        return { title: raw, mapper: "", difficulty: "" };
    return { title: match[1], mapper: match[2], difficulty: match[3] };
}
