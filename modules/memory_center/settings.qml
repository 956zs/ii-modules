import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.memory_center

/*
 * Settings fragment rendered inside the Modules page (Item root, minimal API
 * surface). Options live in ~/.config/illogical-impulse/modules/memory_center.json.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader { id: cfg }

    ConfigSwitch {
        text: Translation.tr("Show the bar widget")
        buttonIcon: "memory"
        checked: cfg.options.showBar
        onCheckedChanged: {
            cfg.options.showBar = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Off frees bar space (stock's Resources widget already shows a memory dial) — the panel stays reachable via the sidebar tile or IPC.")
    }

    ConfigSwitch {
        text: Translation.tr("Show percentage in the bar")
        buttonIcon: "percent"
        checked: cfg.options.showBarPercent
        onCheckedChanged: {
            cfg.options.showBarPercent = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Off shows the icon only — the pressure colour still carries the state.")
    }

    ConfigSpinBox {
        icon: "av_timer"
        text: Translation.tr("Memory poll interval (ms)")
        value: cfg.options.meminfoInterval
        from: 500
        to: 10000
        stepSize: 500
        onValueChanged: {
            cfg.options.meminfoInterval = value;
        }
    }

    ConfigSpinBox {
        icon: "timer"
        text: Translation.tr("Process poll interval while the panel is open (ms)")
        value: cfg.options.procInterval
        from: 1000
        to: 15000
        stepSize: 500
        onValueChanged: {
            cfg.options.procInterval = value;
        }
    }

    ConfigSpinBox {
        icon: "grid_view"
        text: Translation.tr("Process blocks in the panel")
        value: cfg.options.blockCount
        from: 4
        to: 24
        stepSize: 1
        onValueChanged: {
            cfg.options.blockCount = value;
        }
    }

    ConfigSpinBox {
        icon: "warning"
        text: Translation.tr("Warning colour from used (%)")
        value: cfg.options.warnPercent
        from: 50
        to: 100
        stepSize: 5
        onValueChanged: {
            cfg.options.warnPercent = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Sidebar tile: to show a Memory tile in the right sidebar's quick toggles, add this entry to sidebar.quickToggles.android.toggles in the shell's config.json (the tile editor only offers stock types):")
    }

    MaterialTextField {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        readOnly: true
        text: "{\"type\": \"memory_center\", \"size\": 1}"
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/memory_center.json"
    }
}
