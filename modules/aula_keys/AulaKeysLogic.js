.pragma library

// Pure helpers for the AULA key overlay. `aulactl feed` prints one JSON
// object per line (contract: aulactl docs/feed.md); this file turns those
// lines into safe events, keeps the press counters and the KPS window, and
// decides when the overlay (and with it the feed process) should run.

var DEFAULT_KEYS = ["KeyZ", "KeyX"];
var MAX_KEYS = 16;
var MODES = ["playing", "focused", "always", "off"];
var CORNERS = ["bottomRight", "bottomLeft", "bottomCenter", "topRight", "topLeft", "topCenter"];
var KPS_WINDOW_MS = 1000;
var BACKOFF_MIN_MS = 1000;
var BACKOFF_MAX_MS = 30000;

// DOM KeyboardEvent.code shape, the names the feed uses ("KeyZ", "Digit1",
// "Semicolon", "ShiftLeft").
var CODE_RE = /^[A-Z][A-Za-z0-9]{1,23}$/;

function finite(value, fallback) {
    if (value === null || value === undefined || value === "")
        return fallback;
    var n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

function clamp(value, lo, hi, fallback) {
    var n = finite(value, fallback);
    return Math.min(hi, Math.max(lo, n));
}

function oneOf(value, allowed, fallback) {
    return allowed.indexOf(value) !== -1 ? value : fallback;
}

function normalizeMode(mode) {
    return oneOf(mode, MODES, "playing");
}

function normalizeCorner(corner) {
    return oneOf(corner, CORNERS, "bottomRight");
}

// "KeyZ, KeyX" / "KeyD KeyF KeyJ KeyK" -> ["KeyZ", "KeyX"]. Invalid names
// are dropped, duplicates keep their first position, and an empty or fully
// invalid list falls back to the osu! standard default.
function parseKeyList(text) {
    var out = [];
    if (typeof text === "string") {
        var parts = text.split(/[\s,;]+/);
        for (var i = 0; i < parts.length && out.length < MAX_KEYS; i++) {
            var code = parts[i].trim();
            if (CODE_RE.test(code) && out.indexOf(code) === -1)
                out.push(code);
        }
    }
    return out.length > 0 ? out : DEFAULT_KEYS.slice();
}

var NAMED = {
    Space: "Space", Enter: "Enter", Tab: "Tab", Backspace: "Bksp", Escape: "Esc",
    CapsLock: "Caps", ShiftLeft: "LShift", ShiftRight: "RShift", ControlLeft: "LCtrl",
    ControlRight: "RCtrl", AltLeft: "LAlt", AltRight: "RAlt", MetaLeft: "Super",
    MetaRight: "Super", Semicolon: ";", Quote: "'", Comma: ",", Period: ".", Slash: "/",
    Backslash: "\\", BracketLeft: "[", BracketRight: "]", Minus: "-", Equal: "=",
    Backquote: "`", ContextMenu: "Menu", Fn: "Fn"
};

// Keycap text before the feed's hello supplies its own labels.
function keyLabel(code) {
    if (typeof code !== "string" || code === "")
        return "?";
    if (/^Key[A-Z]$/.test(code))
        return code.slice(3);
    if (/^Digit[0-9]$/.test(code))
        return code.slice(5);
    if (NAMED.hasOwnProperty(code))
        return NAMED[code];
    return code;
}

// Arguments after the binary: `feed --keys KeyZ,KeyX [--depth-hz N]`.
function feedArgs(keys, depthHz) {
    var args = ["feed", "--keys", keys.join(",")];
    var hz = Math.round(finite(depthHz, 0));
    if (hz > 0)
        args.push("--depth-hz", String(hz));
    return args;
}

function str(value) {
    return typeof value === "string" ? value : "";
}

function parseHelloKey(raw) {
    if (!raw || typeof raw !== "object" || typeof raw.code !== "string" || raw.code === "")
        return null;
    var label = str(raw.label).trim();
    return {
        code: raw.code,
        label: label !== "" ? label : keyLabel(raw.code),
        mode: str(raw.mode),
        point: Math.max(0, finite(raw.point, 0)),
        press: Math.max(0, finite(raw.press, 0)),
        release: Math.max(0, finite(raw.release, 0))
    };
}

// One stdout line -> a normalized event, or null for anything outside the
// contract (blank, not JSON, unknown type, missing key). Never throws.
function parseLine(line) {
    if (typeof line !== "string")
        return null;
    var text = line.trim();
    if (text === "" || text.charAt(0) !== "{")
        return null;
    var data;
    try {
        data = JSON.parse(text);
    } catch (error) {
        return null;
    }
    if (!data || typeof data !== "object")
        return null;
    var t = finite(data.t, NaN);
    switch (data.type) {
    case "status":
        if (data.state !== "waiting" && data.state !== "lost")
            return null;
        return { type: "status", state: data.state, reason: str(data.reason) };
    case "hello":
        var keys = [];
        if (Array.isArray(data.keys)) {
            for (var i = 0; i < data.keys.length; i++) {
                var key = parseHelloKey(data.keys[i]);
                if (key)
                    keys.push(key);
            }
        }
        return {
            type: "hello",
            product: str(data.product),
            firmware: str(data.firmware),
            maxMm: Math.max(0, finite(data.max_mm, 0)),
            keys: keys
        };
    case "depth":
        if (typeof data.key !== "string" || data.key === "")
            return null;
        var mm = finite(data.mm, NaN);
        if (!Number.isFinite(mm))
            return null;
        return { type: "depth", t: t, key: data.key, mm: Math.max(0, mm) };
    case "press":
    case "release":
        if (typeof data.key !== "string" || data.key === "")
            return null;
        return { type: data.type, t: t, key: data.key };
    case "error":
        return { type: "error", msg: str(data.msg) };
    default:
        return null;
    }
}

// Coarse status shown under the keycaps. Reasons are free-form feed text,
// so only "busy" is singled out (another aulactl/aula-gui holds the board).
function statusKind(event) {
    if (!event)
        return "";
    if (event.type === "error")
        return "error";
    if (event.type !== "status")
        return "";
    if (event.state === "lost")
        return "lost";
    return event.reason === "busy" ? "busy" : "waiting";
}

// Fraction of full travel for the depth bar, 0..1.
function travelFraction(mm, maxMm) {
    var max = finite(maxMm, 0);
    if (max <= 0)
        return 0;
    return clamp(finite(mm, 0) / max, 0, 1, 0);
}

// ---- counters and KPS ----------------------------------------------------

// Mutable counter state, owned by one KeyFeed instance.
function newStats() {
    return { counts: {}, total: 0, presses: [], peak: 0, clockT: NaN, clockWall: 0 };
}

// Forget the KPS window (feed restarted: its `t` base starts over).
function resetWindow(stats) {
    stats.presses = [];
    stats.clockT = NaN;
    stats.clockWall = 0;
    return stats;
}

function resetCounts(stats) {
    stats.counts = {};
    stats.total = 0;
    stats.peak = 0;
    return resetWindow(stats);
}

// Current time on the feed's clock: the last event's `t` advanced by the
// wall time since it arrived. NaN before the first timed event.
function feedNow(stats, wallMs) {
    if (!Number.isFinite(stats.clockT))
        return NaN;
    return stats.clockT + Math.max(0, finite(wallMs, 0) - stats.clockWall);
}

// Records the feed clock from an event that carries `t`. A clock running
// backwards means a new feed process, so the old window is meaningless.
function syncClock(stats, t, wallMs) {
    if (!Number.isFinite(t))
        return;
    if (Number.isFinite(stats.clockT) && t < stats.clockT)
        resetWindow(stats);
    stats.clockT = t;
    stats.clockWall = finite(wallMs, 0);
}

function prune(stats, nowT, windowMs) {
    var cutoff = nowT - windowMs;
    var i = 0;
    while (i < stats.presses.length && stats.presses[i] <= cutoff)
        i++;
    if (i > 0)
        stats.presses.splice(0, i);
}

// Presses in the sliding window ending now.
function kps(stats, wallMs, windowMs) {
    var win = finite(windowMs, KPS_WINDOW_MS);
    var now = feedNow(stats, wallMs);
    if (!Number.isFinite(now))
        return 0;
    prune(stats, now, win);
    return stats.presses.length;
}

// Counts a press and returns the KPS right after it. The window count only
// grows at a press, so the peak is exact when sampled here.
function recordPress(stats, key, t, wallMs, windowMs) {
    var win = finite(windowMs, KPS_WINDOW_MS);
    syncClock(stats, t, wallMs);
    var at = Number.isFinite(t) ? t : feedNow(stats, wallMs);
    if (!Number.isFinite(at)) {
        // Untimed feed: fall back to the wall clock as the time base.
        stats.clockT = finite(wallMs, 0);
        stats.clockWall = finite(wallMs, 0);
        at = stats.clockT;
    }
    stats.counts[key] = (stats.counts[key] || 0) + 1;
    stats.total += 1;
    stats.presses.push(at);
    prune(stats, at, win);
    var now = stats.presses.length;
    if (now > stats.peak)
        stats.peak = now;
    return now;
}

// ---- visibility and restart policy ---------------------------------------

// Whether the selected mode wants the overlay for an osu-state value.
function wantVisible(mode, osuState) {
    switch (normalizeMode(mode)) {
    case "always":
        return true;
    case "off":
        return false;
    case "focused":
        return osuState === "menu" || osuState === "playing" || osuState === "cooldown";
    default:
        return osuState === "playing";
    }
}

// Show at once, hide only after `lingerMs` of not wanting: a quick retry
// (playing -> menu -> playing) neither flickers nor restarts the feed.
// Returns the next machine { visible, hideAt }; hideAt > 0 asks the caller
// to re-step at that wall time.
function stepVisibility(machine, want, nowMs, lingerMs) {
    var linger = Math.max(0, finite(lingerMs, 0));
    var visible = !!(machine && machine.visible);
    var hideAt = machine && machine.hideAt > 0 ? machine.hideAt : 0;
    if (want)
        return { visible: true, hideAt: 0 };
    if (!visible)
        return { visible: false, hideAt: 0 };
    if (linger === 0)
        return { visible: false, hideAt: 0 };
    if (hideAt === 0)
        return { visible: true, hideAt: nowMs + linger };
    if (nowMs >= hideAt)
        return { visible: false, hideAt: 0 };
    return { visible: true, hideAt: hideAt };
}

// Restart delay after the feed exited `attempt` times in a row (0-based).
function backoffMs(attempt) {
    var n = Math.max(0, Math.floor(finite(attempt, 0)));
    return Math.min(BACKOFF_MAX_MS, BACKOFF_MIN_MS * Math.pow(2, Math.min(n, 16)));
}
