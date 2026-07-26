import QtQuick
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

    // "org.mozilla.firefox" -> "Firefox", "code-url-handler" -> "Code url handler"
    function appName(appId) {
        if (appId === "__other__") return Translation.tr("Other")
        const last = appId.split(".").pop().replace(/[-_]+/g, " ").trim()
        if (last === "") return appId
        return last.charAt(0).toUpperCase() + last.slice(1)
    }

    function weekdayLetter(dow) {
        return [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"),
                Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"),
                Translation.tr("Sat")][dow] ?? ""
    }
}
