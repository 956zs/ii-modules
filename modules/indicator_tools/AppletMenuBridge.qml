import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.modules.common
import qs.mod.indicator_tools

/*
 * Right-click bridge from a stock status icon to an applet-provided SNI menu.
 * The applet remains the sole owner of menu actions and state.
 */
MouseArea {
    id: root
    required property string appletId
    required property bool styledMenu

    readonly property var trayItem: SystemTray.items.values.find(item => item.id === root.appletId) ?? null

    anchors.fill: parent
    acceptedButtons: Qt.RightButton

    onPressed: event => {
        event.accepted = true
        if (!root.trayItem?.hasMenu)
            return

        if (root.styledMenu) {
            if (menu.active && menu.item)
                menu.item.close()
            else
                menu.active = true
            return
        }

        const window = root.QsWindow.window
        if (!window)
            return
        const p = root.QsWindow.itemPosition(root)
        let x = p.x + root.width / 2
        let y = Config.options.bar.bottom ? p.y : p.y + root.height
        if (Config.options.bar.vertical) {
            x = Config.options.bar.bottom ? p.x : p.x + root.width
            y = p.y + root.height / 2
        }
        root.trayItem.display(window, Math.round(x), Math.round(y))
    }

    onTrayItemChanged: {
        if (!root.trayItem && menu.active && menu.item)
            menu.item.close()
    }

    Loader {
        id: menu
        active: false
        sourceComponent: root.appletId === "nm-applet" ? wifiMenuComponent : appletMenuComponent
    }

    Component {
        id: wifiMenuComponent
        WifiAppletMenu {
            menuHandle: root.trayItem.menu
            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
            Component.onCompleted: open()
            onMenuClosed: menu.active = false
        }
    }

    Component {
        id: appletMenuComponent
        AppletMenu {
            menuHandle: root.trayItem.menu
            semanticStyleId: root.appletId
            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
            Component.onCompleted: open()
            onMenuClosed: menu.active = false
        }
    }

    HyprlandFocusGrab {
        active: menu.active && menu.item !== null
        windows: menu.item ? [menu.item] : []
        onCleared: if (menu.item) menu.item.close()
    }
}
