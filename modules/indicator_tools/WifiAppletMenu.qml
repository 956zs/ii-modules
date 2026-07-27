pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.indicator_tools

PopupWindow {
    id: root

    required property QsMenuHandle menuHandle

    signal menuClosed()
    signal menuOpened(qsWindow: var)

    readonly property real outerMargin: Appearance.sizes.elevationMargin
    readonly property real panelWidth: 436
    readonly property real maxSurfaceHeight: Math.max(280,
        (root.screen?.height ?? 900) - Appearance.sizes.barHeight * 2 - 32)
    readonly property real maxContentHeight: maxSurfaceHeight - 32

    color: "transparent"
    implicitWidth: panelWidth + outerMargin * 2
    implicitHeight: panelSurface.implicitHeight + outerMargin * 2

    function open() {
        root.visible = true
        root.menuOpened(root)
    }

    function close() {
        root.visible = false
        while (stackView.depth > 1)
            stackView.pop()
        root.menuClosed()
    }

    function pushMenu(handle, title, iconName) {
        stackView.push(menuPageComponent.createObject(null, {
            handle,
            pageTitle: title,
            pageIcon: iconName || "wifi"
        }))
    }

    function pushEntries(entries, title, iconName) {
        stackView.push(entriesPageComponent.createObject(null, {
            entries,
            pageTitle: title,
            pageIcon: iconName || "more_horiz"
        }))
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop()
        }

        StyledRectangularShadow {
            target: panelSurface
            opacity: panelSurface.opacity
        }

        Rectangle {
            id: panelSurface
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.outerMargin
            }
            implicitHeight: Math.min((stackView.currentItem?.implicitHeight ?? 0) + 32, root.maxSurfaceHeight)
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            opacity: 0
            Component.onCompleted: opacity = 1

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            StackView {
                id: stackView
                anchors.fill: parent
                anchors.margins: 16
                implicitWidth: root.panelWidth - 32
                implicitHeight: Math.min(currentItem?.implicitHeight ?? 0, root.maxContentHeight)
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}
                initialItem: RootPage {}
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation { duration: 0 }
    }

    component SectionLabel: StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnSurfaceVariant
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colLayer0Border
    }

    component PageHeader: RowLayout {
        id: header
        property string title: ""
        property string iconName: "wifi"
        Layout.fillWidth: true
        spacing: 8

        RippleButton {
            visible: stackView.depth > 1
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: stackView.pop()
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "arrow_back"
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        MaterialSymbol {
            text: header.iconName
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: header.title
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
        }
    }

    component EntryDelegate: WifiAppletMenuEntry {
        required property QsMenuEntry modelData
        menuEntry: modelData
        onDismiss: root.close()
        onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, "wifi")
    }

    component RootPage: Item {
        id: home

        implicitWidth: root.panelWidth - 32
        implicitHeight: Math.min(content.implicitHeight, root.maxContentHeight)

        function clean(text) {
            return String(text ?? "").replace(/_/g, "").replace(/\.\.\.$/, "").trim()
        }

        function lower(entry) {
            return clean(entry?.text).toLowerCase()
        }

        function classify(values) {
            const labeled = values.filter(entry => entry && !entry.isSeparator && clean(entry.text) !== "")
            const result = {
                reliable: false,
                networking: null,
                wifi: null,
                disconnect: null,
                available: null,
                vpn: null,
                current: null,
                information: null,
                edit: null,
                secondary: [],
                management: [],
                unknown: []
            }
            const consumed = []
            let wifiHeading = -1
            let disconnectIndex = -1
            let availableIndex = -1
            let firstManagementIndex = labeled.length

            function take(entry) {
                if (entry && consumed.indexOf(entry) < 0)
                    consumed.push(entry)
                return entry
            }

            for (let i = 0; i < labeled.length; i++) {
                const entry = labeled[i]
                const label = lower(entry)
                if (label === "wi-fi networks" || label === "wifi networks")
                    wifiHeading = i
                else if (label === "disconnect")
                    disconnectIndex = i
                else if (entry.hasChildren && label.startsWith("available network"))
                    availableIndex = i
            }

            if (wifiHeading >= 0 && disconnectIndex === wifiHeading + 2
                    && availableIndex === disconnectIndex + 1) {
                const candidate = labeled[wifiHeading + 1]
                const available = labeled[availableIndex]
                result.reliable = !labeled[wifiHeading].enabled
                    && candidate.enabled
                    && !candidate.hasChildren
                    && available.hasChildren
                if (result.reliable) {
                    result.current = take(candidate)
                    result.disconnect = take(labeled[disconnectIndex])
                    result.available = take(available)
                    take(labeled[wifiHeading])
                }
            }

            if (!result.reliable)
                return result

            for (let i = 0; i < labeled.length; i++) {
                const entry = labeled[i]
                const label = lower(entry)
                if (label === "enable networking") result.networking = take(entry)
                else if (label === "enable wi-fi" || label === "enable wifi") result.wifi = take(entry)
                else if (label === "ethernet network" || (label === "disconnected" && i < wifiHeading)) take(entry)
                else if (entry.hasChildren && (label === "vpn connections" || label === "vpn")) {
                    result.vpn = take(entry)
                    firstManagementIndex = Math.min(firstManagementIndex, i)
                } else if (label === "connection information") {
                    result.information = take(entry)
                    firstManagementIndex = Math.min(firstManagementIndex, i)
                } else if (label.startsWith("edit connections")) {
                    result.edit = take(entry)
                    firstManagementIndex = Math.min(firstManagementIndex, i)
                } else if (label.startsWith("connect to hidden")
                        || label.startsWith("create new wi-fi")
                        || label.startsWith("create new wifi")) {
                    result.management.push(take(entry))
                    firstManagementIndex = Math.min(firstManagementIndex, i)
                }
            }

            for (let i = availableIndex + 1; i < firstManagementIndex; i++) {
                const entry = labeled[i]
                if (consumed.indexOf(entry) < 0)
                    result.secondary.push(take(entry))
            }

            for (const entry of labeled) {
                if (consumed.indexOf(entry) < 0)
                    result.unknown.push(entry)
            }
            return result
        }

        QsMenuOpener {
            id: rootOpener
            menu: root.menuHandle
        }

        readonly property var semantic: home.classify(rootOpener.children.values)
        readonly property var availableEntries: semantic.reliable
            ? availableOpener.children.values.filter(entry => entry && !entry.isSeparator)
            : []
        readonly property var moreEntries: rootOpener.children.values.filter(entry => entry
            && (semantic.management.indexOf(entry) >= 0 || semantic.unknown.indexOf(entry) >= 0))
        readonly property int previewCount: 3

        QsMenuOpener {
            id: availableOpener
            menu: home.semantic.available
        }

        Flickable {
            id: viewport
            anchors.fill: parent
            contentWidth: width
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: content
                width: viewport.width
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42

                        IconImage {
                            anchors.centerIn: parent
                            visible: home.semantic.current?.icon.length > 0
                            source: home.semantic.current?.icon ?? ""
                            asynchronous: true
                            implicitSize: 34
                            mipmap: true
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !(home.semantic.current?.icon.length > 0)
                            text: home.semantic.current ? "wifi" : "signal_wifi_off"
                            iconSize: 34
                            color: home.semantic.current
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: Translation.tr("Wi-Fi")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: home.semantic.current
                                ? home.clean(home.semantic.current.text)
                                : Translation.tr("Applet controls")
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                ColumnLayout {
                    visible: !home.semantic.reliable
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Network controls are available from the applet menu.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1Inactive
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        horizontalPadding: 8
                        buttonRadius: Appearance.rounding.small
                        onClicked: root.pushEntries(rootOpener.children.values,
                            Translation.tr("Applet controls"), "settings")
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol {
                                text: "settings"
                                iconSize: 21
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Applet controls")
                                color: Appearance.colors.colOnSurface
                            }
                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: 20
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: home.semantic.reliable && (home.semantic.networking || home.semantic.wifi)
                    Layout.fillWidth: true
                    spacing: 2

                    SectionLabel { text: Translation.tr("Controls") }

                    Repeater {
                        model: [home.semantic.networking, home.semantic.wifi].filter(entry => entry)
                        delegate: WifiAppletMenuEntry {
                            required property QsMenuEntry modelData
                            menuEntry: modelData
                            iconName: home.lower(modelData).includes("wi-fi") || home.lower(modelData).includes("wifi")
                                ? "wifi"
                                : "public"
                            toggleStyle: true
                            dismissOnTrigger: false
                            onDismiss: root.close()
                            onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, "settings")
                        }
                    }
                }

                Separator { visible: home.semantic.reliable }

                ColumnLayout {
                    visible: home.semantic.reliable
                    Layout.fillWidth: true
                    spacing: 4

                    SectionLabel { text: Translation.tr("Current network") }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24

                                IconImage {
                                    anchors.centerIn: parent
                                    visible: home.semantic.current?.icon.length > 0
                                    source: home.semantic.current?.icon ?? ""
                                    asynchronous: true
                                    implicitSize: 22
                                    mipmap: true
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: !(home.semantic.current?.icon.length > 0)
                                    text: "wifi"
                                    iconSize: 22
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: home.clean(home.semantic.current?.text)
                                    textFormat: Text.PlainText
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    text: Translation.tr("Connected")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1Inactive
                                }
                            }
                        }

                        Repeater {
                            model: home.semantic.disconnect ? [home.semantic.disconnect] : []
                            delegate: WifiAppletMenuEntry {
                                required property QsMenuEntry modelData
                                Layout.preferredWidth: Math.max(118, implicitWidth)
                                menuEntry: modelData
                                iconName: "link_off"
                                actionStyle: true
                                onDismiss: root.close()
                                onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, "link_off")
                            }
                        }
                    }
                }

                ColumnLayout {
                    visible: home.semantic.reliable && home.semantic.available
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        SectionLabel { text: Translation.tr("Available networks") }
                        RippleButton {
                            visible: home.availableEntries.length > home.previewCount
                            implicitHeight: 28
                            horizontalPadding: 7
                            buttonRadius: Appearance.rounding.small
                            onClicked: root.pushMenu(home.semantic.available,
                                Translation.tr("Available networks"), "wifi_find")
                            contentItem: StyledText {
                                text: Translation.tr("View all")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }

                    Repeater {
                        model: home.availableEntries.slice(0, home.previewCount)
                        delegate: WifiAppletMenuEntry {
                            required property QsMenuEntry modelData
                            menuEntry: modelData
                            iconName: "wifi"
                            onDismiss: root.close()
                            onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, "wifi")
                        }
                    }

                    StyledText {
                        visible: home.availableEntries.length === 0
                        Layout.fillWidth: true
                        text: Translation.tr("No networks found")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                }

                ColumnLayout {
                    visible: home.semantic.reliable && home.semantic.secondary.length > 0
                    Layout.fillWidth: true
                    spacing: 2

                    SectionLabel { text: Translation.tr("Other devices") }
                    Repeater {
                        model: home.semantic.secondary
                        delegate: EntryDelegate {
                            iconName: modelData.enabled ? "power_settings_new" : "lan"
                        }
                    }
                }

                Separator {
                    visible: home.semantic.reliable && (home.semantic.vpn
                        || home.semantic.information || home.semantic.edit || home.moreEntries.length > 0)
                }

                ColumnLayout {
                    visible: home.semantic.reliable && (home.semantic.vpn
                        || home.semantic.information || home.semantic.edit || home.moreEntries.length > 0)
                    Layout.fillWidth: true
                    spacing: 6

                    SectionLabel { text: Translation.tr("Connections") }

                    Repeater {
                        model: home.semantic.vpn ? [home.semantic.vpn] : []
                        delegate: WifiAppletMenuEntry {
                            required property QsMenuEntry modelData
                            menuEntry: modelData
                            iconName: "vpn_key"
                            onDismiss: root.close()
                            onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, "vpn_key")
                        }
                    }

                    RowLayout {
                        visible: home.semantic.information || home.semantic.edit
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [home.semantic.information, home.semantic.edit].filter(entry => entry)
                            delegate: WifiAppletMenuEntry {
                                required property QsMenuEntry modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                menuEntry: modelData
                                iconName: modelData === home.semantic.information ? "info" : "settings"
                                labelOverride: modelData === home.semantic.information
                                    ? Translation.tr("Information")
                                    : Translation.tr("Edit connections")
                                actionStyle: true
                                onDismiss: root.close()
                                onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, "settings")
                            }
                        }
                    }

                    RippleButton {
                        visible: home.moreEntries.length > 0
                        Layout.fillWidth: true
                        implicitHeight: 36
                        horizontalPadding: 6
                        buttonRadius: Appearance.rounding.small
                        onClicked: root.pushEntries(home.moreEntries, Translation.tr("More"), "more_horiz")
                        contentItem: RowLayout {
                            spacing: 10
                            MaterialSymbol {
                                text: "more_horiz"
                                iconSize: 21
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("More")
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: String(home.moreEntries.length)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: 20
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: content.implicitHeight > viewport.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
        }
    }

    component MenuPage: Item {
        id: menuPage
        required property QsMenuHandle handle
        property string pageTitle: ""
        property string pageIcon: "wifi"

        implicitWidth: root.panelWidth - 32
        implicitHeight: Math.min(menuContent.implicitHeight, root.maxContentHeight)
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: pageOpener
            menu: menuPage.handle
        }

        Flickable {
            id: menuViewport
            anchors.fill: parent
            contentWidth: width
            contentHeight: menuContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: menuContent
                width: menuViewport.width
                spacing: 6

                PageHeader {
                    title: menuPage.pageTitle
                    iconName: menuPage.pageIcon
                }

                Repeater {
                    model: pageOpener.children
                    delegate: WifiAppletMenuEntry {
                        required property QsMenuEntry modelData
                        menuEntry: modelData
                        iconName: menuPage.pageIcon === "vpn_key" ? "vpn_key" : "wifi"
                        onDismiss: root.close()
                        onOpenSubmenu: (handle, title) => root.pushMenu(handle, title, menuPage.pageIcon)
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: menuContent.implicitHeight > menuViewport.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
        }
    }

    component EntriesPage: Item {
        id: entriesPage
        required property var entries
        property string pageTitle: ""
        property string pageIcon: "more_horiz"

        implicitWidth: root.panelWidth - 32
        implicitHeight: Math.min(entriesContent.implicitHeight, root.maxContentHeight)
        StackView.onRemoved: destroy()

        Flickable {
            id: entriesViewport
            anchors.fill: parent
            contentWidth: width
            contentHeight: entriesContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: entriesContent
                width: entriesViewport.width
                spacing: 6

                PageHeader {
                    title: entriesPage.pageTitle
                    iconName: entriesPage.pageIcon
                }

                Repeater {
                    model: entriesPage.entries
                    delegate: EntryDelegate {
                        iconName: "more_horiz"
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: entriesContent.implicitHeight > entriesViewport.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
        }
    }

    Component { id: menuPageComponent; MenuPage {} }
    Component { id: entriesPageComponent; EntriesPage {} }
}
