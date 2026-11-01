import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.aula_keys
import "AulaKeysLogic.js" as Logic

/*
 * Quick settings shown when the bar icon is clicked. Every control writes
 * the same module config file as the settings page (through the bar's
 * ConfigLoader); the live line reads the window slot's feed via the hub.
 */
ColumnLayout {
    id: root

    required property ConfigLoader config
    // main.qml registered in AulaHub.js, or null while it is not loaded.
    property var owner: null
    // Logic.barState value from the bar entry.
    property string barState: "off"
    // Translated feed/board state line from the bar entry.
    property string stateText: ""

    readonly property var opts: root.config.options
    readonly property var feed: root.owner ? root.owner.feed : null

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: "keyboard"
            iconSize: Appearance.font.pixelSize.huge
            color: root.barState === "live" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("AULA key overlay")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.stateText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledText {
        visible: root.barState === "live" && root.feed !== null
        Layout.fillWidth: true
        Layout.bottomMargin: 2
        font.family: Appearance.font.family.numbers
        font.features: ({ "tnum": 1 })
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer1
        text: root.feed ? Translation.tr("%1 KPS · peak %2 · total %3").arg(root.feed.kpsNow).arg(root.feed.peak).arg(root.feed.total) : ""
    }

    StyledText {
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Show the overlay")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: root.opts.mode
        onSelected: newValue => {
            root.opts.mode = newValue;
        }
        options: [
            {
                displayName: Translation.tr("While playing osu!"),
                icon: "sports_esports",
                value: "playing"
            },
            {
                displayName: Translation.tr("While osu! is focused"),
                icon: "center_focus_strong",
                value: "focused"
            },
            {
                displayName: Translation.tr("Always"),
                icon: "visibility",
                value: "always"
            },
            {
                displayName: Translation.tr("Off"),
                icon: "visibility_off",
                value: "off"
            }
        ]
    }

    StyledText {
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Keys")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: Logic.presetFor(root.opts.keys)
        onSelected: newValue => {
            // "Custom" only marks a list that matches no preset; editing it
            // stays in the settings page.
            if (Logic.PRESETS.hasOwnProperty(newValue))
                root.opts.keys = Logic.PRESETS[newValue];
        }
        options: [
            {
                displayName: Translation.tr("osu! standard"),
                icon: "radio_button_checked",
                value: "standard"
            },
            {
                displayName: Translation.tr("mania 4K"),
                icon: "view_week",
                value: "mania4k"
            },
            {
                displayName: Translation.tr("mania 7K"),
                icon: "view_column",
                value: "mania7k"
            },
            {
                displayName: Translation.tr("Custom"),
                icon: "edit",
                value: "custom"
            }
        ]
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Logic.parseKeyList(root.opts.keys).join(" ")
    }

    StyledText {
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Key travel")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: Logic.normalizeTravelStyle(root.opts.travelStyle)
        onSelected: newValue => {
            root.opts.travelStyle = newValue;
        }
        options: [
            {
                displayName: Translation.tr("Fill"),
                icon: "water_full",
                value: "fill"
            },
            {
                displayName: Translation.tr("Side bar"),
                icon: "vertical_align_bottom",
                value: "bar"
            },
            {
                displayName: Translation.tr("Off"),
                icon: "visibility_off",
                value: "off"
            }
        ]
    }

    ConfigSwitch {
        Layout.topMargin: 4
        text: Translation.tr("Press count under each key")
        buttonIcon: "tag"
        checked: root.opts.showCounts
        onCheckedChanged: {
            if (root.config.ready && !root.config.materializing)
                root.opts.showCounts = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("KPS, peak and total line")
        buttonIcon: "speed"
        checked: root.opts.showStats
        onCheckedChanged: {
            if (root.config.ready && !root.config.materializing)
                root.opts.showStats = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Reset counters for every new session")
        buttonIcon: "restart_alt"
        checked: root.opts.resetOnSession
        onCheckedChanged: {
            if (root.config.ready && !root.config.materializing)
                root.opts.resetOnSession = checked;
        }
    }

    RippleButton {
        Layout.topMargin: 4
        Layout.alignment: Qt.AlignRight
        buttonText: Translation.tr("Reset counters now")
        onClicked: root.opts.resetRequest = root.opts.resetRequest + 1
    }
}
