import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.clock_popup_slim

ColumnLayout {
    spacing: 4

    ConfigLoader {
        id: config
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("These options customize the horizontal bar clock. The vertical bar keeps its stock layout.")
    }

    ConfigSwitch {
        text: Translation.tr("Show date on the bar")
        buttonIcon: "calendar_month"
        checked: config.options.showDate
        onCheckedChanged: {
            if (config.ready && !config.materializing)
                config.options.showDate = checked;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10

        StyledText {
            text: Translation.tr("Time format")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: "HH:mm"
            text: config.options.timeFormat
            onEditingFinished: config.options.timeFormat = text
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10
        enabled: config.options.showDate

        StyledText {
            text: Translation.tr("Date format")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: "ddd, dd/MM"
            text: config.options.dateFormat
            onEditingFinished: config.options.dateFormat = text
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10
        enabled: config.options.showDate

        StyledText {
            text: Translation.tr("Separator")
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialTextField {
            Layout.fillWidth: true
            placeholderText: "•"
            text: config.options.separator
            onEditingFinished: config.options.separator = text
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Qt date/time patterns are supported. Use HH:mm for a 24-hour clock, hh:mm AP for a 12-hour clock, and add :ss for seconds.")
    }

    ConfigSpinBox {
        icon: "space_bar"
        text: Translation.tr("Content spacing (px)")
        value: config.options.contentSpacing
        from: 0
        to: 24
        stepSize: 1
        onValueChanged: {
            if (config.ready && !config.materializing)
                config.options.contentSpacing = value;
        }
    }

    ConfigSpinBox {
        icon: "width_normal"
        text: Translation.tr("Horizontal padding (px)")
        value: config.options.horizontalPadding
        from: 0
        to: 32
        stepSize: 1
        onValueChanged: {
            if (config.ready && !config.materializing)
                config.options.horizontalPadding = value;
        }
    }

    ConfigSpinBox {
        icon: "compress"
        text: Translation.tr("Center side width (px)")
        value: config.options.centerSideWidth
        from: 280
        to: 360
        stepSize: 10
        onValueChanged: {
            if (config.ready && !config.materializing)
                config.options.centerSideWidth = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Reduces the left and right center sections equally, keeping Workspaces at the exact screen center. The clock remains left-aligned in the right section.")
    }

    ConfigSpinBox {
        icon: "text_fields"
        text: Translation.tr("Time text size offset (px)")
        value: config.options.timeSizeOffset
        from: -4
        to: 8
        stepSize: 1
        onValueChanged: {
            if (config.ready && !config.materializing)
                config.options.timeSizeOffset = value;
        }
    }

    ConfigSpinBox {
        icon: "format_size"
        text: Translation.tr("Date text size offset (px)")
        enabled: config.options.showDate
        value: config.options.dateSizeOffset
        from: -4
        to: 8
        stepSize: 1
        onValueChanged: {
            if (config.ready && !config.materializing)
                config.options.dateSizeOffset = value;
        }
    }

    ConfigSwitch {
        text: Translation.tr("Slim hover popup")
        buttonIcon: "unfold_less"
        checked: config.options.slimPopup
        onCheckedChanged: {
            if (config.ready && !config.materializing)
                config.options.slimPopup = checked;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("When enabled, the hover popup hides system uptime and To Do. Disable it to restore the complete stock popup.")
    }
}
