import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/*
 * Shared formatting helpers (instance, not a singleton). Non-visual QtObject:
 * instantiate inside a visual Item or behind a property, never as a direct
 * BarGroup child.
 */
QtObject {
    // 23145 -> "6h 26m", 754 -> "13m", 30 -> "<1m", 0 -> "0m"
    function dur(seconds) {
        const s = Math.max(0, Math.round(seconds))
        if (s === 0) return "0m"
        if (s < 60) return "<1m"
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (h === 0) return `${m}m`
        return m === 0 ? `${h}h` : `${h}h ${m}m`
    }

    // Compact for tight spots (vertical bar, axis labels): "6.4h" / "26m"
    function durCompact(seconds) {
        const s = Math.max(0, Math.round(seconds))
        if (s < 60) return "0m"
        if (s < 3600) return `${Math.floor(s / 60)}m`
        const h = s / 3600
        return h < 10 ? `${h.toFixed(1)}h` : `${Math.round(h)}h`
    }

    // "org.mozilla.firefox" -> "Firefox", "Minecraft* 1.20.1" -> "Minecraft 1.20.1"
    function appName(appId) {
        if (typeof appId !== "string" || appId === "") return ""
        if (appId === "__other__") return Translation.tr("Other")

        const steamMatch = appId.match(/^steam_app_(\d+)$/i)
        if (steamMatch) {
            const runUri = `steam://rungameid/${steamMatch[1]}`
            const entry = DesktopEntries.applications.values.find(candidate =>
                candidate.command && candidate.command.some(argument => argument === runUri))
            if (entry && entry.name) return entry.name
        }

        const desktopEntry = DesktopEntries.heuristicLookup(appId)
        if (desktopEntry && desktopEntry.name) return desktopEntry.name

        const reverseDomain = /^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z][A-Za-z0-9_-]*)+$/.test(appId)
        const source = reverseDomain ? appId.split(".").pop() : appId
        const readable = source.replace(/\*/g, " ").replace(/[-_]+/g, " ")
            .replace(/\s+/g, " ").trim()
        if (readable === "") return appId
        return readable.charAt(0).toUpperCase() + readable.slice(1)
    }

    function weekdayLetter(dow) {
        return [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"),
                Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"),
                Translation.tr("Sat")][dow] ?? ""
    }
}
