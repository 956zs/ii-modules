import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.battery_trend

/*
 * Settings fragment rendered inside the Modules page (Item root, minimal API
 * surface). Options live in ~/.config/illogical-impulse/modules/battery_trend.json.
 * This loader is read-only for the history blob (owner stays false); the bar
 * widget's primary instance owns defaults and flushes.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader { id: cfg }

    ConfigSpinBox {
        icon: "av_timer"
        text: Translation.tr("Sampling interval (seconds)")
        value: cfg.options.samplingIntervalSec
        from: 15
        to: 600
        stepSize: 15
        onValueChanged: {
            cfg.options.samplingIntervalSec = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Raw samples are kept for 24 hours at this interval; longer history is downsampled, so the file stays small either way.")
    }

    ConfigSwitch {
        text: Translation.tr("Keep 30 days of hourly history")
        buttonIcon: "calendar_view_week"
        checked: cfg.options.keepHourly
        onCheckedChanged: {
            cfg.options.keepHourly = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Keep 365 days of daily history and health snapshots")
        buttonIcon: "calendar_month"
        checked: cfg.options.keepDaily
        onCheckedChanged: {
            cfg.options.keepDaily = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Record charge/discharge sessions")
        buttonIcon: "power"
        checked: cfg.options.keepSessions
        onCheckedChanged: {
            cfg.options.keepSessions = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Turning a tier off stops collecting it; already-stored data ages out on its own.")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10

        StyledText {
            text: Translation.tr("Battery")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("auto = detect via UPower (e.g. BAT0)")
            text: cfg.options.batteryName
            onEditingFinished: {
                cfg.options.batteryName = text.trim() === "" ? "auto" : text.trim();
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/battery_trend.json"
    }
}
