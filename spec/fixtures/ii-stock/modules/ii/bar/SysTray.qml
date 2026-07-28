import QtQuick

Item {
    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems
    property bool showSeparator: true

    MaterialSymbol {
            text: "•"
            visible: root.showSeparator && SystemTray.items.values.length > 0
    }
}
