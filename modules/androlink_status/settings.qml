import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.androlink_status

/*
 * Settings fragment rendered inside the Modules page (Item root). Options
 * live in ~/.config/illogical-impulse/modules/androlink_status.json; the
 * timing options (heartbeat, re-read, action timeout, re-arm margin) are
 * file-only and documented in the README.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader {
        id: cfg
    }

    ConfigSwitch {
        text: Translation.tr("Show while androlink isn't running")
        buttonIcon: "mobile_off"
        checked: cfg.options.showWhenNotRunning
        onCheckedChanged: {
            cfg.options.showWhenNotRunning = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Off hides the capsule while androlink is closed. On keeps a dim phone icon in the bar.")
    }

    ConfigSwitch {
        text: Translation.tr("Show unread notification count")
        buttonIcon: "notifications"
        checked: cfg.options.showUnread
        onCheckedChanged: {
            cfg.options.showUnread = checked;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Low battery reminder")
        buttonIcon: "battery_alert"
        checked: cfg.options.lowBatteryReminder
        onCheckedChanged: {
            cfg.options.lowBatteryReminder = checked;
        }
    }

    ConfigSpinBox {
        enabled: cfg.options.lowBatteryReminder
        icon: "battery_2_bar"
        text: Translation.tr("Reminder level (percent)")
        value: cfg.options.lowBatteryThreshold
        from: 1
        to: 95
        stepSize: 5
        onValueChanged: {
            cfg.options.lowBatteryThreshold = value;
        }
    }

    ConfigSpinBox {
        enabled: cfg.options.lowBatteryReminder
        icon: "timer"
        text: Translation.tr("Shortest gap between reminders (minutes)")
        value: cfg.options.reminderMinIntervalMins
        from: 0
        to: 1440
        stepSize: 5
        onValueChanged: {
            cfg.options.reminderMinIntervalMins = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("One reminder per discharge. It comes back after the phone charges or climbs %1 points above this level.").arg(cfg.options.rearmMargin)
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 6
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Reads $XDG_RUNTIME_DIR/androlink/status.json written by androlink. Panel actions run the androlink command and nothing else.")
    }
}
