import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.network_traffic

/*
 * Settings fragment rendered inside the Modules page (Item root, minimal API
 * surface). Options live in ~/.config/illogical-impulse/modules/network_traffic.json.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader { id: cfg }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Bar layout")
    }

    ConfigSelectionArray {
        Layout.fillWidth: false
        Layout.leftMargin: 8
        currentValue: cfg.options.displayMode
        onSelected: newValue => {
            cfg.options.displayMode = newValue;
        }
        options: [
            {
                displayName: Translation.tr("Auto"),
                icon: "auto_awesome",
                value: "auto"
            },
            {
                displayName: Translation.tr("Stacked"),
                icon: "table_rows",
                value: "stacked"
            },
            {
                displayName: Translation.tr("Single line"),
                icon: "view_column",
                value: "horizontal"
            },
        ]
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Stacked roughly thirds the widget width. Use it where the bar's right section runs out of room and starts overlapping the clock and battery.")
    }

    ConfigSpinBox {
        icon: "width_normal"
        text: Translation.tr("Auto: stack at or below this screen width (px)")
        enabled: cfg.options.displayMode === "auto"
        value: cfg.options.autoStackMaxWidth
        from: 800
        to: 7680
        stepSize: 160
        onValueChanged: {
            if (cfg.ready && !cfg.materializing) cfg.options.autoStackMaxWidth = value;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Direction arrows when stacked")
        buttonIcon: "swap_vert"
        checked: cfg.options.stackedShowIcons
        onCheckedChanged: {
            if (cfg.ready && !cfg.materializing) cfg.options.stackedShowIcons = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Per-app usage accounting")
        buttonIcon: "apps"
        checked: cfg.options.appMonitoring
        onCheckedChanged: {
            if (cfg.ready && !cfg.materializing) cfg.options.appMonitoring = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Samples continuously via nethogs to build boot/today/month per-app totals. Turn off to save power on battery.")
    }

    ConfigSpinBox {
        icon: "av_timer"
        text: Translation.tr("Update interval (ms)")
        value: cfg.options.updateInterval
        from: 500
        to: 10000
        stepSize: 500
        onValueChanged: {
            if (cfg.ready && !cfg.materializing) cfg.options.updateInterval = value;
        }
    }

    ConfigSpinBox {
        icon: "heart_plus"
        text: Translation.tr("Arrows breathe above (KiB/s)")
        value: cfg.options.breatheThresholdKB
        from: 64
        to: 65536
        stepSize: 256
        onValueChanged: {
            if (cfg.ready && !cfg.materializing) cfg.options.breatheThresholdKB = value;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10

        StyledText {
            text: Translation.tr("Ping target")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("auto = your DNS server")
            text: cfg.options.pingHost
            onEditingFinished: {
                cfg.options.pingHost = text.trim() === "" ? "auto" : text.trim();
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/network_traffic.json"
    }
}
