import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.discord_presence

/*
 * Settings fragment rendered inside the Modules page (Item root). Options
 * live in ~/.config/illogical-impulse/modules/discord_presence.json.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader {
        id: cfg
    }

    ConfigSwitch {
        text: Translation.tr("Hide when no game is detected")
        buttonIcon: "visibility_off"
        checked: cfg.options.hideWhenIdle
        onCheckedChanged: {
            cfg.options.hideWhenIdle = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("While hidden, the pill comes back when a game is detected or presence is paused. It also stays hidden while the daemon is not running.")
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnLayer1
        font.weight: Font.DemiBold
        text: Translation.tr("discord-rpc-proxy command")
    }

    MaterialTextField {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        placeholderText: Translation.tr("Command name or path")
        text: cfg.options.binary
        onEditingFinished: cfg.options.binary = text.trim() !== "" ? text.trim() : "discord-rpc-proxy"
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("A name is looked up in PATH and ~/ is expanded. The pill only runs its watch and toggle subcommands; it detects nothing itself.")
    }
}
