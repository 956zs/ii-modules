import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.screentime

/*
 * Settings fragment rendered inside the Modules page (Item root, minimal API
 * surface). Options live in ~/.config/illogical-impulse/modules/screentime.json.
 */
ColumnLayout {
    spacing: 4

    ConfigLoader { id: cfg }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10

        StyledText {
            text: Translation.tr("Excluded apps")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: Translation.tr("comma-separated, e.g. mpv, org.mozilla.firefox")
            text: cfg.options.excludedApps
            onEditingFinished: {
                cfg.options.excludedApps = text.trim();
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Focus time in these apps is never counted (substring match against the window's appId/class, case-insensitive).")
    }

    ConfigSpinBox {
        icon: "airline_seat_recline_extra"
        text: Translation.tr("Idle gap threshold (s)")
        value: cfg.options.idleGapSec
        from: 30
        to: 600
        stepSize: 15
        onValueChanged: {
            cfg.options.idleGapSec = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("A wall-clock jump longer than this between samples (suspend, hibernate) is treated as away time and not counted.")
    }

    ConfigSwitch {
        text: Translation.tr("Keep 30-day history")
        buttonIcon: "calendar_month"
        checked: cfg.options.keepHistory
        onCheckedChanged: {
            cfg.options.keepHistory = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Off wipes the daily history and keeps only today. Locked-screen time is never counted.")
    }

    ConfigSwitch {
        text: Translation.tr("Track AI agent work time")
        buttonIcon: "smart_toy"
        checked: cfg.options.aiTracking
        onCheckedChanged: {
            cfg.options.aiTracking = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Samples the CPU of matching processes every 10 s; a session whose process tree exceeds the threshold counts as working — even unfocused or with the screen locked. Its own stat, never mixed into focused screen time.")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10

        StyledText {
            text: Translation.tr("Agent process regex")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: "^(claude|codex)$"
            text: cfg.options.aiProcessRegex
            onEditingFinished: {
                cfg.options.aiProcessRegex = text.trim();
            }
        }
    }

    ConfigSpinBox {
        icon: "speed"
        text: Translation.tr("Working threshold (% CPU)")
        value: cfg.options.aiActiveCpuPct
        from: 1
        to: 50
        stepSize: 1
        onValueChanged: {
            cfg.options.aiActiveCpuPct = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Percent of one CPU core per sample window. An agent CLI idle at its prompt measures 0%, a working one 20%+ — the default 1% separates them with margin.")
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.topMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Sidebar tile: to show a Screen Time tile in the right sidebar's quick toggles, add this entry to sidebar.quickToggles.android.toggles in the shell's config.json (the tile editor only offers stock types):")
    }

    MaterialTextField {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        readOnly: true
        text: "{\"type\": \"screentime\", \"size\": 1}"
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/screentime.json"
    }
}
