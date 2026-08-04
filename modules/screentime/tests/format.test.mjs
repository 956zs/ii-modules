import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"
import vm from "node:vm"

const formatQml = fs.readFileSync(new URL("../Format.qml", import.meta.url), "utf8")

function loadFunction(name) {
    const match = formatQml.match(new RegExp(`function ${name}\\([^]*?\\n    }`))
    assert.ok(match, `${name} must exist in Format.qml`)

    return vm.runInNewContext(`(${match[0]})`, {
        DesktopEntries: {
            heuristicLookup: appId => appId === "org.prismlauncher.PrismLauncher"
                ? { name: "Prism Launcher" }
                : null,
            applications: {
                values: [
                    {
                        command: ["steam", "steam://rungameid/438100"],
                        name: "VRChat"
                    }
                ]
            }
        },
        Translation: { tr: value => value }
    })
}

const appName = loadFunction("appName")

test("resolves VRChat's Steam app ID to its game name", () => {
    assert.equal(appName("steam_app_438100"), "VRChat")
})

test("keeps generic desktop app IDs readable", () => {
    assert.equal(appName("org.mozilla.firefox"), "Firefox")
    assert.equal(appName("code-url-handler"), "Code url handler")
})

test("does not mistake a dotted Minecraft version for a reverse-domain app ID", () => {
    assert.equal(appName("Minecraft* 1.20.1"), "Minecraft 1.20.1")
})

test("prefers the desktop entry name when the app ID resolves", () => {
    assert.equal(appName("org.prismlauncher.PrismLauncher"), "Prism Launcher")
})

test("handles aggregate, empty, invalid, and unknown Steam IDs", () => {
    assert.equal(appName("__other__"), "Other")
    assert.equal(appName(""), "")
    assert.equal(appName(null), "")
    assert.equal(appName("steam_app_999999999"), "Steam app 999999999")
})
