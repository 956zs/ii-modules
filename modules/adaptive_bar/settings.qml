import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.adaptive_bar

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
        text: Translation.tr("When the right side of the horizontal bar runs out of room, pinned tray icons fold into the tray overflow menu first, then both center sections shrink equally. Workspaces stay at the exact screen center.")
    }

    ConfigSpinBox {
        icon: "width_normal"
        text: Translation.tr("Maximum center side width (px)")
        value: config.options.centerSideMaxWidth
        from: 190
        to: 360
        stepSize: 10
        onValueChanged: {
            if (config.ready && !config.materializing)
                config.options.centerSideMaxWidth = value;
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
        text: Translation.tr("Caps the left and right center sections even when there is room. 360 keeps the stock width; the stock narrow-screen widths still apply below it.")
    }
}
