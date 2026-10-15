import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.osu_indicator

/*
 * Settings fragment rendered inside the Modules page (Item root). Options
 * live in ~/.config/illogical-impulse/modules/osu_indicator.json.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader {
        id: cfg
    }

    ConfigSwitch {
        text: Translation.tr("Show while osu! is in the background")
        buttonIcon: "visibility"
        checked: cfg.options.showWhenIdle
        onCheckedChanged: {
            cfg.options.showWhenIdle = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Show while osu! is in the menus")
        buttonIcon: "menu"
        checked: cfg.options.showWhenMenu
        onCheckedChanged: {
            cfg.options.showWhenMenu = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Both off: the pill appears only while a map is being played or just finished.")
    }

    ConfigSwitch {
        text: Translation.tr("Show play time and cooldown countdown")
        buttonIcon: "timer"
        checked: cfg.options.showTimer
        onCheckedChanged: {
            cfg.options.showTimer = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Approach circle animation while playing")
        buttonIcon: "animation"
        checked: cfg.options.approachAnimation
        onCheckedChanged: {
            cfg.options.approachAnimation = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("Accent colour")
    }

    ConfigSelectionArray {
        Layout.fillWidth: true
        currentValue: cfg.options.accent
        onSelected: newValue => {
            cfg.options.accent = newValue;
        }
        options: [
            {
                displayName: Translation.tr("Theme"),
                icon: "palette",
                value: "theme"
            },
            {
                displayName: Translation.tr("osu! pink"),
                icon: "favorite",
                value: "osu"
            }
        ]
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("The pill reads $XDG_RUNTIME_DIR/osu-state.json written by the osu-state daemon; it detects nothing itself.")
    }
}
