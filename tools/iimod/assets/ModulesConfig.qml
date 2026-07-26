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
                required property int index
                readonly property bool moduleOn: card.modelData.state === "enabled"
                readonly property bool flippable: card.modelData.state === "enabled" || card.modelData.state === "disabled"
                property bool busy: false
                property bool showSettings: false
                property string lastFlipError: ""
                // Loaded lazily on first open and kept mounted afterwards
                // (only clipped away by the Revealer below) so collapsing
                // never discards the settings fragment's own state.
                property bool settingsEverOpened: false

                Layout.fillWidth: true
                implicitHeight: cardColumn.implicitHeight + 10 * 2
                radius: Appearance.rounding.small
                color: cardHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                opacity: 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                HoverHandler {
                    id: cardHover
                }

                // Quick staggered fade-in on page load; capped so a long
                // module list doesn't drag the reveal out.
                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { duration: Math.min(card.index * 25, 150) }
                    NumberAnimation {
                        target: card
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Component.onCompleted: enterAnim.start()

                // Runs iimod; PATH may lack ~/.local/bin in a session-launched
                // settings app, so fall back to the conventional install path.
                Process {
                    id: flipProc
                    property string wanted: ""
                    property string lastError: ""
                    command: ["sh", "-c",
                        `bin=$(command -v iimod || echo "$HOME/.local/bin/iimod"); exec "$bin" ${wanted} ${card.modelData.id}`]
                    stderr: StdioCollector {
                        id: flipStderr
                        onStreamFinished: flipProc.lastError = flipStderr.text
                    }
                    onExited: (exitCode, exitStatus) => {
                        card.busy = false;
                        // The index projection reload is the real sync; snap
                        // the switch back explicitly on failure.
                        moduleSwitch.checked = Qt.binding(() => card.moduleOn);
                        if (exitCode !== 0) {
                            console.warn(`[iimp] iimod ${wanted} ${card.modelData.id} failed (${exitCode}): ${flipProc.lastError.trim()}`);
                            card.lastFlipError = flipProc.lastError.trim();
                        } else {
                            card.lastFlipError = "";
                        }
                    }
                }

                function flip(on) {
                    if (card.busy) return;
                    card.busy = true;
                    card.lastFlipError = "";
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
                            onClicked: {
                                card.showSettings = !card.showSettings;
                                if (card.showSettings) card.settingsEverOpened = true;
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "settings"
                                iconSize: Appearance.font.pixelSize.larger
                                color: card.showSettings ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1
                                rotation: card.showSettings ? 180 : 0
                                Behavior on rotation {
                                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                }
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }

                        MaterialSymbol {
                            id: busySpinner
                            text: "progress_activity"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1Inactive
                            opacity: card.busy ? 1 : 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            RotationAnimation on rotation {
                                running: card.busy
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                                easing.type: Easing.Linear
                            }
                        }

                        StyledSwitch {
                            id: moduleSwitch
                            enabled: card.flippable && !card.busy
                            checked: card.moduleOn
                            opacity: card.busy ? 0.5 : 1
                            onClicked: card.flip(!card.moduleOn)
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
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

                    // Last flip failure, if any; cleared as soon as another
                    // attempt starts (see flip()).
                    RowLayout {
                        Layout.fillWidth: true
                        visible: card.lastFlipError.length > 0
                        spacing: 4

                        MaterialSymbol {
                            text: "error"
                            iconSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3error
                        }
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3error
                            wrapMode: Text.WordWrap
                            text: card.lastFlipError
                        }
                    }

                    // Per-module placement on vertical (left/right) bars.
                    // Host-level concern, so it lives here, not in the
                    // module's own settings fragment. Reassign the whole map:
                    // mutating a key inside a var property emits no change
                    // signal, so the bar would never react.
                    RowLayout {
                        visible: (card.modelData.slots ?? []).indexOf("bar") !== -1
                        spacing: 8

                        MaterialSymbol {
                            text: "swap_vert"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            text: Translation.tr("Vertical bar position")
                        }
                        ConfigSelectionArray {
                            Layout.fillWidth: false
                            currentValue: ((Config.options.iimp?.barPlacements ?? ({}))[card.modelData.id] ?? "top")
                            onSelected: newValue => {
                                const next = Object.assign({}, Config.options.iimp.barPlacements ?? ({}));
                                next[card.modelData.id] = newValue;
                                Config.options.iimp.barPlacements = next;
                            }
                            options: [
                                { displayName: Translation.tr("Top"), icon: "vertical_align_top", value: "top" },
                                { displayName: Translation.tr("Above tray"), icon: "vertical_align_bottom", value: "bottom" },
                            ]
                        }
                    }

                    // Unfolded settings fragment (only meaningful when the
                    // module is on — its config file is still the module's own
                    // either way). The Revealer animates the height so the
                    // gear unfold doesn't hard-pop the layout.
                    Revealer {
                        id: settingsRevealer
                        Layout.fillWidth: true
                        Layout.topMargin: settingsRevealer.visible ? 4 : 0
                        vertical: true
                        reveal: card.showSettings

                        Loader {
                            width: settingsRevealer.width
                            active: card.settingsEverOpened && card.modelData.settings
                            source: active ? Quickshell.shellPath(`mod/${card.modelData.id}/${card.modelData.settings}`) : ""
                            onStatusChanged: if (status === Loader.Error) console.warn(`[iimp] settings fragment failed: ${card.modelData.id}`)
                        }
                    }
                }
            }
        }
    }
}
