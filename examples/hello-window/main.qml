import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/*
 * Window slot entry: MUST root Scope, PanelWindow, or LazyLoader.
 * Instantiated by the IIMP ModuleHost via Qt.createComponent.
 */
Scope {
    PanelWindow {
        anchors {
            top: true
            right: true
        }
        margins {
            top: 10
            right: 10
        }
        implicitWidth: greeting.implicitWidth + 24
        implicitHeight: greeting.implicitHeight + 16
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer0

            StyledText {
                id: greeting
                anchors.centerIn: parent
                color: Appearance.colors.colOnLayer0
                text: "hello from IIMP"
            }
        }
    }
}
