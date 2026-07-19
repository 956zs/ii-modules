// IIMP settings page — installed and owned by iimod. DO NOT EDIT (recomposed on reapply).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true
    property var mods: []

    function isEnabled(id) {
        return (Config.options.iimp?.enabledBar ?? []).includes(id)
            || (Config.options.iimp?.enabledWindow ?? []).includes(id);
    }

    FileView {
        path: Directories.shellConfig + "/modules/index.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.mods = JSON.parse(text()).modules;
            } catch (e) {
                root.mods = [];
            }
        }
        onLoadFailed: root.mods = []
    }

    ContentSection {
        icon: "extension"
        title: Translation.tr("Installed modules")

        StyledText {
            visible: root.mods.length === 0
            text: Translation.tr("No modules installed. Install with: iimod install <package>")
        }

        Repeater {
            model: root.mods
            delegate: ConfigSwitch {
                required property var modelData
                text: (modelData.name[Translation.languageCode] ?? modelData.name.en_US)
                      + "  ·  v" + modelData.version
                      + (modelData.state === "incompatible" ? "  (" + Translation.tr("incompatible") + ")" : "")
                enabled: modelData.state !== "incompatible" && modelData.state !== "blocked-by-dep"
                checked: root.isEnabled(modelData.id)
                onCheckedChanged: {
                    if (checked === root.isEnabled(modelData.id))
                        return; // programmatic update, not a user action
                    for (const slot of modelData.slots) {
                        const key = slot === "bar" ? "enabledBar" : "enabledWindow";
                        const cur = [...(Config.options.iimp[key] ?? [])];
                        const has = cur.includes(modelData.id);
                        if (checked && !has)
                            Config.options.iimp[key] = [...cur, modelData.id].sort();
                        else if (!checked && has)
                            Config.options.iimp[key] = cur.filter(x => x !== modelData.id);
                    }
                }
            }
        }
    }

    Repeater {
        model: root.mods.filter(m => m.settings && root.isEnabled(m.id))
        delegate: ContentSection {
            required property var modelData
            icon: "tune"
            title: modelData.name[Translation.languageCode] ?? modelData.name.en_US
            Loader {
                Layout.fillWidth: true
                source: Quickshell.shellPath(`mod/${modelData.id}/${modelData.settings}`)
                onStatusChanged: if (status === Loader.Error) console.warn(`[iimp] settings fragment failed: ${modelData.id}`)
            }
        }
    }
}
