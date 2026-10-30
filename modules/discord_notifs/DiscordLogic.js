.pragma library

// Pure helpers: classify a desktop notification coming from Discord and shape it for display.
// Discord (desktop client) notification formats observed in the wild:
//   DM / group DM : summary "Sender"                         body "message"
//   server        : summary "Sender (#channel, Server)"      body "message"
//   forum/thread  : summary "Sender (Post title in #forum, Server)"
//   reaction      : body "Reacted :emoji: to you \"...\""
//   system        : summary "Quest Completed!" and similar, no sender/location

// First-strong-isolate marks Discord wraps around names, plus zero-width characters.
var INVISIBLE = /[⁦-⁩​-‏‪-‮﻿]/g

function clean(text) {
    return String(text === undefined || text === null ? "" : text).replace(INVISIBLE, "").trim()
}

// Parses an app-name list stored as a JSON string option; falls back to the given defaults.
function parseList(json, fallback) {
    try {
        var v = JSON.parse(json)
        if (Array.isArray(v) && v.length > 0)
            return v.map(function (s) { return String(s).toLowerCase() })
    } catch (e) {}
    return fallback
}

function isDiscord(appName, appNames) {
    return appNames.indexOf(String(appName || "").toLowerCase()) >= 0
}

// kind: "dm" | "server" | "system"
function classify(summary, body) {
    var s = clean(summary).replace(/\s*\n\s*/g, " ")
    var b = clean(body)
    var reaction = /^Reacted\s/.test(b)
    var m = s.match(/^(.*?)\s*\(([^()]*)\)$/)
    if (m && /#/.test(m[2])) {
        // "(#channel, Server)" or "(Post title in #forum, Server)": the last comma splits the server off.
        var loc = m[2]
        var cut = loc.lastIndexOf(", ")
        return {
            kind: "server", reaction: reaction, sender: m[1],
            channel: cut >= 0 ? loc.slice(0, cut) : loc,
            server: cut >= 0 ? loc.slice(cut + 2) : ""
        }
    }
    if (s === "" || /\b(quest|nitro|orbs?)\b/i.test(s) || /^(Discord|Friend request)/i.test(s))
        return { kind: "system", reaction: reaction, sender: s, channel: "", server: "" }
    return { kind: "dm", reaction: reaction, sender: s, channel: "", server: "" }
}

function matchesFilter(kind, filter) {
    if (filter === "all") return true
    if (filter === "dm") return kind === "dm"
    if (filter === "server") return kind === "server"
    if (filter === "other") return kind === "system"
    return true
}

var FILTERS = ["all", "dm", "server", "other"]

function nextFilter(current) {
    var i = FILTERS.indexOf(current)
    return FILTERS[(i + 1) % FILTERS.length]
}

function isFilter(name) {
    return FILTERS.indexOf(name) >= 0
}

// Entries newest first, Discord only, filtered, capped. `list` items need appName/summary/body/time/image.
function select(list, appNames, filter, maxItems) {
    var out = []
    for (var i = 0; i < list.length; i++) {
        var n = list[i]
        if (!isDiscord(n.appName, appNames)) continue
        var c = classify(n.summary, n.body)
        out.push({
            id: n.notificationId, time: n.time, image: n.image || "",
            kind: c.kind, reaction: c.reaction, sender: c.sender,
            channel: c.channel, server: c.server, body: clean(n.body)
        })
    }
    var counts = { all: out.length, dm: 0, server: 0, other: 0 }
    for (var j = 0; j < out.length; j++) {
        if (out[j].kind === "dm") counts.dm++
        else if (out[j].kind === "server") counts.server++
        else counts.other++
    }
    out.sort(function (a, b) { return b.time - a.time })
    var shown = out.filter(function (e) { return matchesFilter(e.kind, filter) })
    return { items: shown.slice(0, Math.max(1, maxItems | 0)), counts: counts }
}

// Short relative time. `now` and `time` are epoch milliseconds. Returns {unit, n}, unit in now|min|hour|day.
function ago(now, time) {
    var sec = Math.max(0, Math.floor((now - time) / 1000))
    if (sec < 60) return { unit: "now", n: 0 }
    if (sec < 3600) return { unit: "min", n: Math.floor(sec / 60) }
    if (sec < 86400) return { unit: "hour", n: Math.floor(sec / 3600) }
    return { unit: "day", n: Math.floor(sec / 86400) }
}
