.pragma library

// Hand-off between this module's entries. The window slot (main.qml) owns
// the feed and registers itself here; bar entries (one per monitor) read
// live state from it. A `.pragma library` script is instantiated once per
// QML engine, so every entry of this module sees the same variable. Nothing
// outside the module imports this file.

var owner = null;

function register(object) {
    owner = object;
}

function unregister(object) {
    if (owner === object)
        owner = null;
}

function current() {
    return owner;
}
