.pragma library

function hasControlCharacters(value) {
    for (let index = 0; index < value.length; index++) {
        const code = value.charCodeAt(index);
        if (code < 32 || code === 127)
            return true;
    }
    return false;
}

function safeFormat(value, fallback) {
    if (typeof value !== "string")
        return fallback;
    const candidate = value.trim();
    if (candidate.length === 0 || candidate.length > 64 || hasControlCharacters(candidate))
        return fallback;
    return candidate;
}

function safeSeparator(value, fallback) {
    if (typeof value !== "string" || value.length > 8 || hasControlCharacters(value))
        return fallback;
    return value;
}

function clampInteger(value, minimum, maximum, fallback) {
    const number = Number(value);
    if (!Number.isFinite(number))
        return fallback;
    return Math.max(minimum, Math.min(maximum, Math.round(number)));
}

function needsSecondPrecision(format) {
    const value = safeFormat(format, "HH:mm");
    let quoted = false;
    for (let index = 0; index < value.length; index++) {
        if (value[index] === "'") {
            if (value[index + 1] === "'") {
                index++;
                continue;
            }
            quoted = !quoted;
        } else if (!quoted && value[index] === "s") {
            return true;
        }
    }
    return false;
}
