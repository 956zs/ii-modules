import QtQuick

Item {
    id: root

    property var monitor
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)
}
