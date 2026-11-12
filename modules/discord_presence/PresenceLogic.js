.pragma library

// Pure helpers for the Discord presence pill. `discord-rpc-proxy watch`
// prints one JSON status line at start and one per change; this file turns
// a line into a safe record and derives what the bar and popup display.
// Plain ES5 on purpose: Quickshell's JS engine rejects some newer syntax.

var DEFAULT_BINARY = "discord-rpc-proxy";
// Retry cadence for `watch`: the daemon is not running (or the binary is
// missing), so poll slowly; a stream that delivered lines and then ended is
// most likely a daemon restart, so try again soon.
var RETRY_MS = 10000;
var QUICK_RETRY_MS = 1000;

function finite(value, fallback) {
    if (typeof value !== "number" && typeof value !== "string")
        return fallback;
    var n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

// Record while no watch stream is connected: daemon not running.
function downState() {
    return { up: false, paused: false, away: false, connected: false, game: null };
}

function parseGame(game) {
    if (!game || typeof game !== "object" || Array.isArray(game))
        return null;
    var id = typeof game.id === "string" ? game.id.trim() : "";
    var name = typeof game.name === "string" ? game.name.trim() : "";
    if (name === "")
        name = id;
    if (name === "")
        return null;
    var playtime = finite(game.playtime_secs, -1);
    return {
        id: id,
        name: name,
        pid: Math.max(0, Math.floor(finite(game.pid, 0))),
        startedAt: Math.max(0, Math.floor(finite(game.started_at, 0))),
        // -1: play time tracking is off (the daemon sends null).
        playtimeSecs: playtime >= 0 ? Math.floor(playtime) : -1,
        shown: game.shown === true
    };
}

// Parses one status line. Returns null for anything that is not a status
// object, so a stray line never replaces the last good state.
function parseStatus(text) {
    if (typeof text !== "string" || text.trim() === "")
        return null;
    var data;
    try {
        data = JSON.parse(text);
    } catch (error) {
        return null;
    }
    if (!data || typeof data !== "object" || Array.isArray(data))
        return null;
    if (typeof data.paused !== "boolean")
        return null;
    return {
        up: true,
        paused: data.paused,
        away: data.away === true,
        connected: data.discord_connected === true,
        game: parseGame(data.game)
    };
}

// "down" | "paused" | "playing" | "idle".
function kind(record) {
    if (!record || !record.up)
        return "down";
    if (record.paused)
        return "paused";
    return record.game ? "playing" : "idle";
}

// Whether the pill is on the bar. With hideWhenIdle the pill shows only
// while a game is detected or presence is paused.
function shownFor(record, hideWhenIdle) {
    if (hideWhenIdle !== true)
        return true;
    var k = kind(record);
    return k === "playing" || k === "paused";
}

// Small badge on the icon: "disconnected" beats "away"; none while down
// (the dimmed icon already says it) or while everything is fine.
function marker(record) {
    if (!record || !record.up)
        return "";
    if (!record.connected)
        return "disconnected";
    if (record.away)
        return "away";
    return "";
}

// Text beside the icon: the detected game's name, or nothing.
function barText(record) {
    return record && record.up && record.game ? record.game.name : "";
}

// Seconds since the game was detected, never negative.
function elapsed(record, nowSecs) {
    if (!record || !record.game || !record.game.startedAt)
        return 0;
    return Math.max(0, Math.floor(finite(nowSecs, 0) - record.game.startedAt));
}

// Total play time now. The daemon sends the total when a line is printed and
// keeps counting while a game is detected and the owner is not away, without
// printing new lines for it, so extrapolate from when the line arrived.
// -1 when unknown.
function playtimeNow(record, receivedSecs, nowSecs) {
    if (!record || !record.up || !record.game || record.game.playtimeSecs < 0)
        return -1;
    var base = record.game.playtimeSecs;
    if (record.away)
        return base;
    var grown = Math.floor(finite(nowSecs, 0) - finite(receivedSecs, 0));
    return base + Math.max(0, grown);
}

// "m:ss", or "h:mm:ss" past an hour.
function formatClock(secs) {
    var total = Math.max(0, Math.floor(finite(secs, 0)));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var mm = h > 0 && m < 10 ? "0" + m : String(m);
    var ss = s < 10 ? "0" + s : String(s);
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
}

// Whole hours and zero-padded minutes for "%1 h %2 min".
function splitHours(secs) {
    var total = Math.max(0, Math.floor(finite(secs, 0)));
    var m = Math.floor((total % 3600) / 60);
    return { hours: Math.floor(total / 3600), minutes: m, paddedMinutes: m < 10 ? "0" + m : String(m) };
}

// Whether the 1 s ticker is needed: only the popup shows running times.
function needsTicker(record, popupOpen) {
    return popupOpen === true && !!record && record.up === true && !!record.game;
}

function retryDelayMs(hadLine) {
    return hadLine === true ? QUICK_RETRY_MS : RETRY_MS;
}

// Executable from the settings: trimmed, "~/" expanded (Process does not
// run a shell), empty falls back to the default name looked up in PATH.
function resolveBinary(value, home) {
    var bin = typeof value === "string" ? value.trim() : "";
    if (bin === "")
        return DEFAULT_BINARY;
    if (bin === "~" || bin.indexOf("~/") === 0) {
        var base = typeof home === "string" ? home.replace(/\/+$/, "") : "";
        if (base === "")
            return bin;
        return base + bin.slice(1);
    }
    return bin;
}
