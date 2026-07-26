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
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/memory_center.json"
    }
}
