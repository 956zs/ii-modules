// IIMP settings page — installed and owned by iimod. DO NOT EDIT (recomposed on reapply).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * One card per installed module: toggle, Tier badge, description, and a gear
 * that unfolds the module's settings fragment in place.
 *
 * Toggling runs `iimod enable/disable` instead of editing the config lists
 * directly: iimod is the single source of truth — it flips the registry,
 * rewrites the enabled-list projection (Tier A widgets react live), and
 * recomposes stock files when a Tier B module's patches enter or leave the
 * composition. The switch reflects the index projection and is re-synced
 * from it after every attempt, so a failed flip snaps back.
 */
ContentPage {
    id: root
    forceWidth: true
    property var mods: []

    function isEnabled(id) {
        const m = root.mods.find(x => x.id === id);
        return (m?.state ?? "") === "enabled";
    }

    function localized(dict, fallback) {
        if (!dict) return fallback ?? "";
        return dict[Translation.languageCode] ?? dict.en_US ?? fallback ?? "";
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
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool moduleOn: card.modelData.state === "enabled"
                readonly property bool flippable: card.modelData.state === "enabled" || card.modelData.state === "disabled"
                property bool busy: false
                property bool showSettings: false

                Layout.fillWidth: true
                implicitHeight: cardColumn.implicitHeight + 10 * 2
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                // Runs iimod; PATH may lack ~/.local/bin in a session-launched
                // settings app, so fall back to the conventional install path.
                Process {
                    id: flipProc
                    property string wanted: ""
                    command: ["sh", "-c",
                        `bin=$(command -v iimod || echo "$HOME/.local/bin/iimod"); exec "$bin" ${wanted} ${card.modelData.id}`]
                    onExited: (exitCode, exitStatus) => {
                        card.busy = false;
                        // The index projection reload is the real sync; snap
                        // the switch back explicitly on failure.
                        moduleSwitch.checked = Qt.binding(() => card.moduleOn);
                        if (exitCode !== 0)
                            console.warn(`[iimp] iimod ${wanted} ${card.modelData.id} failed (${exitCode})`);
                    }
                }

                function flip(on) {
                    if (card.busy) return;
                    card.busy = true;
                    flipProc.wanted = on ? "enable" : "disable";
                    flipProc.running = true;
                }

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 10
                    }
                    spacing: 4

                    RowLayout {
                        spacing: 8

                        StyledText {
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            text: root.localized(card.modelData.name, card.modelData.id)
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1Inactive
                            text: "v" + card.modelData.version
                        }
                        Rectangle {
                            visible: card.modelData.tierB === true
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSecondaryContainer
                            implicitWidth: tierText.implicitWidth + 8 * 2
                            implicitHeight: tierText.implicitHeight + 2 * 2
                            StyledText {
                                id: tierText
                                anchors.centerIn: parent
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSecondaryContainer
                                text: Translation.tr("patches stock files")
                            }
                        }
                        StyledText {
                            visible: !card.flippable
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3error
                            text: card.modelData.state === "incompatible"
                                  ? Translation.tr("incompatible")
                                  : Translation.tr("blocked by dependency")
                        }

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            visible: card.modelData.settings !== null && card.modelData.settings !== undefined
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            toggled: card.showSettings
                            onClicked: card.showSettings = !card.showSettings
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "settings"
                                iconSize: Appearance.font.pixelSize.larger
                                color: card.showSettings ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                            }
                        }

                        StyledSwitch {
                            id: moduleSwitch
                            enabled: card.flippable && !card.busy
                            checked: card.moduleOn
                            onClicked: card.flip(!card.moduleOn)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        wrapMode: Text.WordWrap
                        text: root.localized(card.modelData.description, "")
                    }

                    // Unfolded settings fragment (only meaningful when the
                    // module is on — its config file is still the module's own
                    // either way).
                    Loader {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        active: card.showSettings && card.modelData.settings
                        visible: active
                        source: active ? Quickshell.shellPath(`mod/${card.modelData.id}/${card.modelData.settings}`) : ""
                        onStatusChanged: if (status === Loader.Error) console.warn(`[iimp] settings fragment failed: ${card.modelData.id}`)
                    }
                }
            }
        }
    }
}
