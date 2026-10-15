import QtQuick

Item {
    id: root
    property bool vertical: false
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showSeparator: true
    property bool showOverflowMenu: true

    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems

    GridLayout {
        rowSpacing: 8
        columnSpacing: 15

        RippleButton {
            id: trayOverflowButton
            visible: root.showOverflowMenu && root.unpinnedItems.length > 0

            StyledPopup {
                id: overflowPopup
                hoverTarget: trayOverflowButton

                GridLayout {
                    id: trayOverflowLayout
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.unpinnedItems

                        delegate: SysTrayItem {
                            item: modelData
                        }
                    }
                }
            }
        }

        Repeater {
            model: root.pinnedItems

            delegate: SysTrayItem {
                item: modelData
                onMenuOpened: (qsWindow) => {
                    root.setExtraWindowAndGrabFocus(qsWindow);
                }
            }
        }

        MaterialSymbol {
            text: "•"
            visible: root.showSeparator && SystemTray.items.values.length > 0
        }
    }
}
