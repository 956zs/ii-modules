import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/*
 * Settings fragment rendered inside the Modules page (Item root, minimal API
 * surface). Options live in ~/.config/illogical-impulse/modules/network-traffic.json.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader { id: cfg }

    StyledText {
        Layout.fillWidth: true
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Update interval (ms):") + " " + cfg.options.updateInterval
              + "\n" + Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/network-traffic.json"
    }
}
