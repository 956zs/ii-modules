import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.mod.clock_popup_slim
import "ClockFormat.js" as ClockFormat

Item {
    id: root

    default property alias popupData: hoverArea.data
    readonly property alias hoverTarget: hoverArea

    ConfigLoader {
        id: config
    }

    readonly property string timeFormat: ClockFormat.safeFormat(config.options.timeFormat, "HH:mm")
    readonly property string dateFormat: ClockFormat.safeFormat(config.options.dateFormat, "ddd, dd/MM")
    readonly property string separator: ClockFormat.safeSeparator(config.options.separator, "•")
    readonly property int contentSpacing: ClockFormat.clampInteger(config.options.contentSpacing, 0, 24, 4)
    readonly property int horizontalPadding: ClockFormat.clampInteger(config.options.horizontalPadding, 0, 32, 0)
    readonly property int centerSideWidth: ClockFormat.clampInteger(config.options.centerSideWidth, 280, 360, 280)
    readonly property int timeSizeOffset: ClockFormat.clampInteger(config.options.timeSizeOffset, -4, 8, 0)
    readonly property int dateSizeOffset: ClockFormat.clampInteger(config.options.dateSizeOffset, -4, 8, 0)

    implicitWidth: content.implicitWidth + root.horizontalPadding * 2
    implicitHeight: Appearance.sizes.barHeight

    SystemClock {
        id: clock
        precision: ClockFormat.needsSecondPrecision(root.timeFormat) ? SystemClock.Seconds : SystemClock.Minutes
    }

    RowLayout {
        id: content
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: root.contentSpacing

        StyledText {
            font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, Appearance.font.pixelSize.large + root.timeSizeOffset)
            color: Appearance.colors.colOnLayer1
            text: Qt.locale().toString(clock.date, root.timeFormat)
        }

        StyledText {
            visible: config.options.showDate && root.separator.length > 0
            font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, Appearance.font.pixelSize.small + root.dateSizeOffset)
            color: Appearance.colors.colOnLayer1
            text: root.separator
        }

        StyledText {
            visible: config.options.showDate
            font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, Appearance.font.pixelSize.small + root.dateSizeOffset)
            color: Appearance.colors.colOnLayer1
            text: Qt.locale().toString(clock.date, root.dateFormat)
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
    }
}
