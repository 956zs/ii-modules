.pragma library

// Pure helpers for the inline reply field. The field lives inside stock
// NotificationItem (modules/common/widgets) through a Tier B patch; these
// helpers keep its decisions testable without Quickshell.

// Keys the field swallows so they never reach the list views or the
// sidebar around it (cursor/scroll navigation, focus chain). Values are
// Qt.Key_* codes: Tab, Backtab, Up, Down, PageUp, PageDown.
var CONTAINED_KEYS = [0x01000001, 0x01000002, 0x01000013, 0x01000015, 0x01000016, 0x01000017];

// Longest reply the field holds (Qt's own TextInput maximum, made explicit
// so the field can say when a paste was cut).
var MAX_REPLY_LENGTH = 32767;

// A reply can be sent only through a live Quickshell Notification that
// advertises an inline-reply action. Restored (persisted) entries have no
// live object, and older Quickshell builds lack the API.
function canReply(live) {
    return !!live && live.hasInlineReply === true && typeof live.sendInlineReply === "function";
}

// Placeholder text: the sender's label for its reply action, else
// `fallback`. The label comes from the sending app, so it is flattened to
// one line and angle brackets become ‹ › (no markup can survive even if a
// Qt text item renders it as rich text); the field also draws it as plain
// text.
function placeholder(live, fallback) {
    var text = live && typeof live.inlineReplyPlaceholder === "string"
        ? live.inlineReplyPlaceholder.replace(/</g, "‹").replace(/>/g, "›").replace(/\s+/g, " ").trim() : "";
    return text !== "" ? text : fallback;
}

// Text to send: trimmed, or "" when there is nothing worth sending.
function replyText(raw) {
    return typeof raw === "string" ? raw.trim() : "";
}

// The stock NotificationGroup hosting `item`: the nearest ancestor that
// carries both `notificationGroup` and a boolean `popup`. Null outside one.
function hostGroup(item) {
    var node = item ? item.parent : null;
    while (node) {
        if (node.notificationGroup !== undefined && typeof node.popup === "boolean")
            return node;
        node = node.parent;
    }
    return null;
}

// After the field lets go of a popup (sent to a resident notification,
// cancelled, or emptied), the popup times out right away unless the pointer
// is still on its group; that is what stock does when the pointer leaves.
function timeoutAfterRelease(notif, group) {
    return !!notif && notif.popup === true && !(group && group.containsMouse === true);
}

function containsKey(key) {
    return CONTAINED_KEYS.indexOf(key) !== -1;
}
