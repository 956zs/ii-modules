import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.modules.common
import qs.mod.indicator_tools

/*
 * Hover-only bridge from a stock status icon to an applet-provided SNI menu.
 * The surrounding stock RippleButton is the sole pointer-event owner; it calls
 * toggleStyledMenu() only when its right-click lands inside this item's bounds.
 * The applet remains the sole owner of menu actions and state.
 */
MouseArea {
    id: root
    required property string appletId
    required property bool styledMenu

    readonly property var trayItem: SystemTray.items.values.find(item => item.id === root.appletId) ?? null
    property bool menuRequested: false
    property bool openWhenLoaded: false
    property var loadedMenu: null
    property rect menuAnchorRect: Qt.rect(0, 0, width, height)

    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    hoverEnabled: true

    function refreshMenuAnchor() {
        const window = root.QsWindow.window
        if (window)
            root.menuAnchorRect = window.itemRect(root)
    }

    function closeStyledMenu() {
        root.openWhenLoaded = false
        root.loadedMenu?.close()
    }

    function toggleStyledMenu() {
        root.refreshMenuAnchor()
        if (!root.loadedMenu) {
            root.openWhenLoaded = true
            root.menuRequested = true
            return
        }
        if (root.loadedMenu.visible)
            root.closeStyledMenu()
        else
            root.loadedMenu.open()
    }

    Component.onCompleted: root.refreshMenuAnchor()
    onEntered: {
        root.refreshMenuAnchor()
        if (root.styledMenu && root.trayItem?.hasMenu)
            root.menuRequested = true
    }

    onTrayItemChanged: {
        if (!root.trayItem) {
            root.openWhenLoaded = false
            root.menuRequested = false
        }
    }

    LazyLoader {
        id: menu
        activeAsync: root.menuRequested && root.styledMenu && root.trayItem?.hasMenu === true
        component: root.appletId === "nm-applet" ? wifiMenuComponent : appletMenuComponent
        onItemChanged: {
            root.loadedMenu = item
            if (item && root.openWhenLoaded) {
                root.openWhenLoaded = false
                item.open()
            }
        }
    }

    Component {
        id: wifiMenuComponent
        WifiAppletMenu {
            menuHandle: root.trayItem.menu
            anchor {
                window: root.QsWindow.window
                rect.x: root.menuAnchorRect.x
                rect.y: root.menuAnchorRect.y
                rect.width: root.menuAnchorRect.width
                rect.height: root.menuAnchorRect.height
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
        }
    }

    Component {
        id: appletMenuComponent
        AppletMenu {
            menuHandle: root.trayItem.menu
            semanticStyleId: root.appletId
            anchor {
                window: root.QsWindow.window
                rect.x: root.menuAnchorRect.x
                rect.y: root.menuAnchorRect.y
                rect.width: root.menuAnchorRect.width
                rect.height: root.menuAnchorRect.height
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
        }
    }
}
