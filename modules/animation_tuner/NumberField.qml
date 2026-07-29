import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RowLayout {
    id: root

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 100
    property int decimals: 0
    property string suffix: ""
    property real stepSize: decimals === 0 ? 1 : Math.pow(10, -decimals)
    property bool valid: true

    signal valueEdited(real value)

    Layout.fillWidth: true
    spacing: 8

    StyledText {
        Layout.fillWidth: true
        text: root.label
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
    MaterialTextField {
        id: field
        Layout.preferredWidth: 112
        Accessible.name: root.label
        Accessible.description: Translation.tr("Range %1 to %2. Use Up and Down to adjust; hold Shift for larger steps.").arg(root.from).arg(root.to)
        text: Number(root.value).toFixed(root.decimals)
        color: acceptableInput ? Appearance.colors.colOnLayer1 : Appearance.m3colors.m3error
        validator: DoubleValidator {
            bottom: root.from
            top: root.to
            decimals: root.decimals
            notation: DoubleValidator.StandardNotation
        }
        onAcceptableInputChanged: root.valid = acceptableInput
        onEditingFinished: {
            const parsed = Number(text)
            if (acceptableInput && Number.isFinite(parsed)) root.valueEdited(parsed)
            else text = Number(root.value).toFixed(root.decimals)
        }
        Keys.onPressed: event => {
            const multiplier = event.modifiers & Qt.ShiftModifier ? 10 : 1
            if (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down) return
            const direction = event.key === Qt.Key_Up ? 1 : -1
            const next = Math.max(root.from, Math.min(root.to, root.value + direction * root.stepSize * multiplier))
            root.valueEdited(next)
            event.accepted = true
        }
    }
    StyledText {
        visible: root.suffix.length > 0
        text: root.suffix
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
