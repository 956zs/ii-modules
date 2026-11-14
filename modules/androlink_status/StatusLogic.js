.pragma library

// Pure helpers for the androlink phone-status module. androlink publishes
// $XDG_RUNTIME_DIR/androlink/status.json (version 1, contract in the androlink
// repository, plans/features-2026-11.md); this file turns its text into a safe
// record, decides what the bar shows, builds the fixed argv for the CLI
// actions, and runs the low-battery reminder state machine.

// Contract values (protocol facts, not tunables).
var ROUTES = ["lan", "tailscale", "other"];
var HELPERS = ["running", "stopped", "not_set_up"];
// A status file older than this many heartbeats means androlink stopped
// rewriting it (crashed or hung).
var STALE_HEARTBEATS = 3;
// The androlink CLI refuses device arguments longer than 64 characters.
var MAX_ID_LENGTH = 64;
// Display cap for a phone name in the bar and the panel.
var MAX_NAME_LENGTH = 64;
// CLI flags the panel may run; anything else is refused.
var DEVICE_FLAGS = ["--ring", "--ring-stop", "--send-clipboard", "--dex"];
var GLOBAL_FLAGS = ["--webcam-stop"];

var CONTROL_CHARS = /[\u0000-\u001f\u007f-\u009f]/;

function finite(value, fallback) {
    var n = Number(value);
    return typeof value !== "boolean" && value !== null && value !== "" && Number.isFinite(n) ? n : fallback;
}

function clampInt(value, low, high, fallback) {
    var n = finite(value, NaN);
    if (!Number.isFinite(n))
        return fallback;
    return Math.min(high, Math.max(low, Math.round(n)));
}

// Record for a status file that cannot be used. `state` tells why:
// "missing" (no file), "invalid" (not the contract), "stopped" (androlink
// quit cleanly and wrote running: false).
function emptyRecord(state) {
    return { state: state, updated: 0, phones: [] };
}

// A device id usable as one argv element: non-empty, bounded, no control
// characters, and never something the CLI could read as a flag.
function validId(value) {
    return typeof value === "string" && value.length > 0 && value.length <= MAX_ID_LENGTH
        && value.trim() === value && !CONTROL_CHARS.test(value) && value.charAt(0) !== "-";
}

function cleanName(value) {
    if (typeof value !== "string")
        return "";
    var name = value.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g, " ").trim();
    return name.length > MAX_NAME_LENGTH ? name.slice(0, MAX_NAME_LENGTH - 1) + "…" : name;
}

function cleanBattery(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return null;
    var level = finite(value.level, NaN);
    if (!Number.isFinite(level))
        return null;
    return { level: Math.min(100, Math.max(0, Math.round(level))), charging: value.charging === true };
}

function cleanPhone(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return null;
    var id = validId(raw.id) ? raw.id : "";
    return {
        id: id,
        name: cleanName(raw.name),
        connected: raw.connected === true,
        route: ROUTES.indexOf(raw.route) !== -1 ? raw.route : null,
        battery: cleanBattery(raw.battery),
        helper: HELPERS.indexOf(raw.helper) !== -1 ? raw.helper : null,
        unread: clampInt(raw.unread, 0, 9999, 0),
        ringing: raw.ringing === true,
        webcam: raw.webcam === true
    };
}

// Parses the status file text. `text` is null when the file could not be
// read. Anything that does not match the contract collapses to a record the
// bar treats as "androlink not running", so a corrupt file can never show a
// made-up phone.
//
// States: missing | invalid | stopped | stale | live.
function parseStatus(text, nowSecs, heartbeatSecs) {
    if (typeof text !== "string" || text.trim() === "")
        return emptyRecord("missing");
    var data;
    try {
        data = JSON.parse(text);
    } catch (error) {
        return emptyRecord("invalid");
    }
    if (!data || typeof data !== "object" || Array.isArray(data))
        return emptyRecord("invalid");
    var version = finite(data.version, NaN);
    if (!Number.isInteger(version) || version < 1)
        return emptyRecord("invalid");
    var updated = finite(data.updated, NaN);
    if (!Number.isFinite(updated) || updated <= 0)
        return emptyRecord("invalid");
    if (data.running !== true) {
        var stopped = emptyRecord("stopped");
        stopped.updated = Math.floor(updated);
        return stopped;
    }
    var phones = [];
    if (Array.isArray(data.phones)) {
        for (var i = 0; i < data.phones.length; i++) {
            var phone = cleanPhone(data.phones[i]);
            if (phone)
                phones.push(phone);
        }
    }
    // A heartbeat published in the file wins over the module option.
    var heartbeat = clampInt(data.heartbeat_s, 1, 86400, NaN);
    if (!Number.isFinite(heartbeat))
        heartbeat = clampInt(heartbeatSecs, 1, 86400, 30);
    var age = finite(nowSecs, 0) - updated;
    return {
        state: age > heartbeat * STALE_HEARTBEATS ? "stale" : "live",
        updated: Math.floor(updated),
        phones: phones
    };
}

// True while androlink is (or recently was) writing the file.
function appRunning(record) {
    return !!record && (record.state === "live" || record.state === "stale");
}

// Index of the phone the bar shows: the first connected one, else the first.
function primaryIndex(record) {
    if (!record || !record.phones || record.phones.length === 0)
        return -1;
    for (var i = 0; i < record.phones.length; i++) {
        if (record.phones[i].connected)
            return i;
    }
    return 0;
}

// What the bar capsule shows. `opts`: showWhenNotRunning, showUnread,
// threshold (low-battery percent).
function barModel(record, opts) {
    var o = opts || {};
    var model = {
        shown: false,
        quiet: false,
        dim: true,
        name: "",
        batteryText: "",
        charging: false,
        low: false,
        helperStopped: false,
        unread: 0,
        ringing: false,
        webcam: false
    };
    if (!appRunning(record)) {
        model.shown = o.showWhenNotRunning === true;
        model.quiet = true;
        return model;
    }
    model.shown = true;
    var stale = record.state === "stale";
    for (var w = 0; w < record.phones.length; w++) {
        if (record.phones[w].webcam)
            model.webcam = true;
    }
    var index = primaryIndex(record);
    if (index === -1)
        return model;
    var phone = record.phones[index];
    model.name = phone.name;
    model.dim = stale || !phone.connected;
    if (phone.battery) {
        model.batteryText = phone.battery.level + "%";
        model.charging = phone.battery.charging;
        model.low = !phone.battery.charging && phone.battery.level <= clampInt(o.threshold, 0, 100, 20);
    }
    model.helperStopped = phone.helper === "stopped";
    model.unread = o.showUnread === false ? 0 : phone.unread;
    model.ringing = phone.ringing && !stale;
    return model;
}

// Fixed argv for one panel action. `flag` "" opens androlink. Device flags
// name the phone by id when several phones are listed; with one phone the
// CLI picks it. Returns null when the action cannot be run safely.
function actionArgs(flag, phone, phoneCount) {
    if (flag === "")
        return ["androlink"];
    if (GLOBAL_FLAGS.indexOf(flag) !== -1)
        return ["androlink", flag];
    if (DEVICE_FLAGS.indexOf(flag) === -1)
        return null;
    if (finite(phoneCount, 0) <= 1)
        return ["androlink", flag];
    if (!phone || !validId(phone.id))
        return null;
    return ["androlink", flag, phone.id];
}

// Outcome of a finished CLI run: "" ok, "notRunning" (exit 1), "noPhone"
// (exit 2: none or ambiguous), "failed" (anything else), "missingCli" when
// the process never started.
function exitKind(exitCode, started) {
    if (started === false)
        return "missingCli";
    if (exitCode === 0)
        return "";
    if (exitCode === 1)
        return "notRunning";
    if (exitCode === 2)
        return "noPhone";
    return "failed";
}

function reminderKey(phone, index) {
    if (phone.id !== "")
        return "id:" + phone.id;
    if (phone.name !== "")
        return "name:" + phone.name;
    return "index:" + index;
}

// Low-battery reminder state machine, one entry per phone. `armed` maps a
// phone key to a boolean (missing = armed). Fires once per discharge cycle
// when the level is at or below `threshold` and the phone is not charging;
// re-arms when the phone charges or the level climbs `margin` points above
// the threshold. Only a live record with a connected phone moves the state:
// a stale or disconnected reading never fires and never re-arms.
//
// Returns { armed: <new map>, fire: [{ key, name, level }] }.
function reminderStep(armed, record, threshold, margin) {
    var next = {};
    var keys = Object.keys(armed || {});
    for (var k = 0; k < keys.length; k++)
        next[keys[k]] = armed[keys[k]] === true;
    var fire = [];
    if (!record || record.state !== "live")
        return { armed: next, fire: fire };
    var limit = clampInt(threshold, 1, 99, 20);
    var rearmAt = limit + clampInt(margin, 1, 50, 5);
    for (var i = 0; i < record.phones.length; i++) {
        var phone = record.phones[i];
        if (!phone.connected || !phone.battery)
            continue;
        var key = reminderKey(phone, i);
        var isArmed = next.hasOwnProperty(key) ? next[key] : true;
        if (phone.battery.charging || phone.battery.level >= rearmAt) {
            isArmed = true;
        } else if (isArmed && phone.battery.level <= limit) {
            fire.push({ key: key, name: phone.name, level: phone.battery.level });
            isArmed = false;
        }
        next[key] = isArmed;
    }
    return { armed: next, fire: fire };
}
