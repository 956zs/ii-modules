import QtQuick

MouseArea {
    id: root
    property var window
    window: root.QsWindow.window
    implicitWidth: 20
    implicitHeight: 20
}
