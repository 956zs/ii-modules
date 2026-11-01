.pragma library

// Pure helpers for the AULA key overlay. `aulactl feed` prints one JSON
// object per line (contract: aulactl docs/feed.md); this file turns those
// lines into safe events, keeps the press counters and the KPS window, and
// decides when the overlay (and with it the feed process) should run.

var DEFAULT_KEYS = ["KeyZ", "KeyX"];
var MAX_KEYS = 16;
var MODES = ["playing", "focused", "always", "off"];
var TRAVEL_STYLES = ["fill", "bar", "off"];
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

function normalizeTravelStyle(style) {
    return oneOf(style, TRAVEL_STYLES, "fill");
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

// ---- bar indicator and quick settings -----------------------------------

// Key presets offered in the settings page and the bar panel.
var PRESETS = {
    standard: "KeyZ,KeyX",
    mania4k: "KeyD,KeyF,KeyJ,KeyK",
    mania7k: "KeyS,KeyD,KeyF,Space,KeyJ,KeyK,KeyL"
};

// Which preset a key list setting matches (after parsing, so spacing and
// separators do not matter), or "custom".
function presetFor(keysText) {
    var keys = parseKeyList(keysText).join(",");
    for (var name in PRESETS) {
        if (PRESETS.hasOwnProperty(name) && PRESETS[name] === keys)
            return name;
    }
    return "custom";
}

// Bar icon state at a glance: "off" (mode off or no overlay owner),
// "hidden" (waiting for osu!), "live", "starting", or "warn" (the feed is
// up but the board is waiting, busy, lost, or the feed failed).
function barState(mode, shown, feedStatus) {
    if (normalizeMode(mode) === "off")
        return "off";
    if (!shown)
        return "hidden";
    switch (feedStatus) {
    case "":
        return "live";
    case "starting":
        return "starting";
    default:
        return "warn";
    }
}

// ---- keycap colours -------------------------------------------------------

// Travel fill opacity along the fill itself, 0 = its top edge, 1 = the
// cap's bottom: the fill fades in from its top edge, so there is no hard
// line where it ends, and it is brighter while the key is pressed.
var FILL_ALPHA_TOP = 0.04;
var FILL_ALPHA_BOTTOM = 0.5;
var PRESSED_BOOST = 1.3;

function fillAlpha(position, pressed) {
    var p = clamp(position, 0, 1, 0);
    var a = FILL_ALPHA_TOP + (FILL_ALPHA_BOTTOM - FILL_ALPHA_TOP) * p;
    return Math.min(1, pressed ? a * PRESSED_BOOST : a);
}

// WCAG relative luminance of {r, g, b} in 0..1 (QML colors qualify).
function luminance(color) {
    if (!color)
        return 0;
    function lin(c) {
        var v = clamp(c, 0, 1, 0);
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * lin(color.r) + 0.7152 * lin(color.g) + 0.0722 * lin(color.b);
}

function contrastRatio(a, b) {
    var la = luminance(a);
    var lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// Colour behind the legend (cap centre): the cap, plus the fill blended in
// once the fill reaches the centre.
function legendBackdrop(cap, accent, fraction, pressed) {
    var f = clamp(fraction, 0, 1, 0);
    if (!cap)
        return { r: 0, g: 0, b: 0 };
    if (!accent || f < 0.5)
        return { r: cap.r, g: cap.g, b: cap.b };
    // Where the cap's centre sits inside the fill's own gradient.
    var a = fillAlpha(1 - 0.5 / f, pressed);
    return {
        r: cap.r + (accent.r - cap.r) * a,
        g: cap.g + (accent.g - cap.g) * a,
        b: cap.b + (accent.b - cap.b) * a
    };
}

// Index (0 or 1) of the candidate that contrasts more with `backdrop`.
function pickContrast(backdrop, first, second) {
    return contrastRatio(backdrop, second) > contrastRatio(backdrop, first) ? 1 : 0;
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

var KEEP_AFTER_PLAY = ["results", "delay"];

function normalizeKeepAfterPlay(value) {
    return oneOf(value, KEEP_AFTER_PLAY, "results");
}

// The osu-state file's `results` flag: true while a results screen is the
// top screen in osu!lazer. Older daemons omit it, which reads as false; so
// does anything that is not exactly `true`. Parsed here rather than in the
// vendored OsuStateLogic.js, which must stay identical to osu_indicator's.
function parseResults(text) {
    if (typeof text !== "string" || text.trim() === "")
        return false;
    try {
        var data = JSON.parse(text);
        return !!data && typeof data === "object" && data.results === true;
    } catch (error) {
        return false;
    }
}

// Whether the selected mode wants the overlay for an osu-state value and
// results flag. `keepAfterPlay` "results" (default) keeps the overlay up
// while the results screen is open; "delay" leaves only the hide delay.
function wantVisible(mode, osuState, results, keepAfterPlay) {
    var onResults = results === true && normalizeKeepAfterPlay(keepAfterPlay) === "results";
    switch (normalizeMode(mode)) {
    case "always":
        return true;
    case "off":
        return false;
    case "focused":
        return osuState === "menu" || osuState === "playing" || osuState === "cooldown" || onResults;
    default:
        return osuState === "playing" || onResults;
    }
}

// A new play (session) starts when the state is "playing" with a start
// time not seen before; opening the results screen never counts.
function newPlayStarted(lastPlaySince, osuState, since) {
    return osuState === "playing" && since !== lastPlaySince;
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
