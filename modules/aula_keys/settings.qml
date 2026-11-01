import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.aula_keys
import "AulaKeysLogic.js" as Logic

/*
 * Settings fragment rendered inside the Modules page (Item root). Options
 * live in ~/.config/illogical-impulse/modules/aula_keys.json; the window
 * slot (main.qml) owns the file and reacts to every change.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader {
        id: cfg
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Show the overlay")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: cfg.options.mode
        onSelected: newValue => {
            cfg.options.mode = newValue;
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
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("osu! state comes from the osu-state daemon. The key feed runs only while the overlay is shown: while it runs, other aulactl and aula-gui commands are refused as busy.")
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Keys")
    }

    MaterialTextField {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        placeholderText: "KeyZ,KeyX"
        text: cfg.options.keys
        onEditingFinished: cfg.options.keys = text
    }

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 4

        RippleButton {
            buttonText: Translation.tr("osu! standard")
            onClicked: cfg.options.keys = Logic.PRESETS.standard
        }
        RippleButton {
            buttonText: Translation.tr("mania 4K")
            onClicked: cfg.options.keys = Logic.PRESETS.mania4k
        }
        RippleButton {
            buttonText: Translation.tr("mania 7K")
            onClicked: cfg.options.keys = Logic.PRESETS.mania7k
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Key codes like KeyZ, Digit1, Space or Semicolon, separated by commas, shown left to right (up to 16).")
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Position")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: cfg.options.corner
        onSelected: newValue => {
            cfg.options.corner = newValue;
        }
        options: [
            {
                displayName: Translation.tr("Top left"),
                icon: "north_west",
                value: "topLeft"
            },
            {
                displayName: Translation.tr("Top centre"),
                icon: "north",
                value: "topCenter"
            },
            {
                displayName: Translation.tr("Top right"),
                icon: "north_east",
                value: "topRight"
            },
            {
                displayName: Translation.tr("Bottom left"),
                icon: "south_west",
                value: "bottomLeft"
            },
            {
                displayName: Translation.tr("Bottom centre"),
                icon: "south",
                value: "bottomCenter"
            },
            {
                displayName: Translation.tr("Bottom right"),
                icon: "south_east",
                value: "bottomRight"
            }
        ]
    }

    ConfigSpinBox {
        icon: "padding"
        text: Translation.tr("Distance from the screen edge (px)")
        value: cfg.options.marginPx
        from: 0
        to: 400
        stepSize: 4
        onValueChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.marginPx = value;
        }
    }

    ConfigSpinBox {
        icon: "zoom_in"
        text: Translation.tr("Size (%)")
        value: cfg.options.scalePercent
        from: 50
        to: 300
        stepSize: 10
        onValueChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.scalePercent = value;
        }
    }

    ConfigSpinBox {
        icon: "opacity"
        text: Translation.tr("Opacity (%)")
        value: cfg.options.opacityPercent
        from: 20
        to: 100
        stepSize: 5
        onValueChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.opacityPercent = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Key travel")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: cfg.options.travelStyle
        onSelected: newValue => {
            cfg.options.travelStyle = newValue;
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

    MaterialTextField {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        placeholderText: Translation.tr("Monitor name, empty for the first screen")
        text: cfg.options.monitor
        onEditingFinished: cfg.options.monitor = text.trim()
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Counters")
    }

    ConfigSwitch {
        text: Translation.tr("Press count under each key")
        buttonIcon: "tag"
        checked: cfg.options.showCounts
        onCheckedChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.showCounts = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("KPS, peak and total line")
        buttonIcon: "speed"
        checked: cfg.options.showStats
        onCheckedChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.showStats = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Show KPS beside the bar icon")
        buttonIcon: "keyboard"
        checked: cfg.options.barShowKps
        onCheckedChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.barShowKps = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Reset counters for every new session")
        buttonIcon: "restart_alt"
        checked: cfg.options.resetOnSession
        onCheckedChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.resetOnSession = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("A session starts when the overlay appears or a new osu! map begins.")
    }

    RippleButton {
        Layout.leftMargin: 8
        buttonText: Translation.tr("Reset counters now")
        onClicked: cfg.options.resetRequest = cfg.options.resetRequest + 1
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Feed")
    }

    ConfigSpinBox {
        icon: "timer"
        text: Translation.tr("Keep shown after leaving osu! (s)")
        value: cfg.options.hideDelaySecs
        from: 0
        to: 60
        stepSize: 1
        onValueChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.hideDelaySecs = value;
        }
    }

    ConfigSpinBox {
        icon: "speed"
        text: Translation.tr("Travel updates per key (Hz, 0 = feed default)")
        value: cfg.options.depthHz
        from: 0
        to: 1000
        stepSize: 10
        onValueChanged: {
            if (cfg.ready && !cfg.materializing)
                cfg.options.depthHz = value;
        }
    }

    MaterialTextField {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        placeholderText: Translation.tr("aulactl command or path")
        text: cfg.options.binary
        onEditingFinished: cfg.options.binary = text.trim() !== "" ? text.trim() : "aulactl"
    }
}
