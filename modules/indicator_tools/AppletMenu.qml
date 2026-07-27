pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.indicator_tools

PopupWindow {
    id: root
    required property QsMenuHandle menuHandle
    property string semanticStyleId: ""

    readonly property real panelWidth: 440
    readonly property real outerMargin: Appearance.sizes.elevationMargin
    readonly property real maxPanelHeight: Math.max(240,
        (root.screen?.height ?? 900) - Appearance.sizes.barHeight * 2 - 32)

    signal menuClosed()
    signal menuOpened(qsWindow: var)

    color: "transparent"
    implicitWidth: panelWidth + outerMargin * 2
    implicitHeight: popupBackground.implicitHeight + outerMargin * 2

    function normalLabel(text) {
        return String(text ?? "").replace(/_/g, "").replace(/\.\.\.$/, "…").trim()
    }

    function deviceName(text, prefix) {
        return normalLabel(text).slice(prefix.length).trim()
    }

    function normalizedDevice(text, prefix) {
        return deviceName(text, prefix).toLocaleLowerCase().replace(/\s+/g, " ")
    }

    function open() {
        visible = true
        menuOpened(root)
    }

    function close() {
        visible = false
        while (stackView.depth > 1)
            stackView.pop()
        menuClosed()
    }

    function openSubmenu(entry, title) {
        stackView.push(subMenuComponent.createObject(null, {
            handle: entry,
            pageTitle: title
        }))
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton)
                    && stackView.depth > 1)
                stackView.pop()
        }

        StyledRectangularShadow {
            target: popupBackground
            opacity: popupBackground.opacity
        }

        Rectangle {
            id: popupBackground
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical ? undefined
                    : Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical ? undefined
                    : Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.outerMargin
            }
            implicitHeight: Math.min(viewport.contentHeight + 32, root.maxPanelHeight)
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

            Flickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: width
                contentHeight: stackView.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                StackView {
                    id: stackView
                    width: viewport.width
                    height: implicitHeight
                    pushEnter: NoAnim {}
                    pushExit: NoAnim {}
                    popEnter: NoAnim {}
                    popExit: NoAnim {}
                    implicitWidth: currentItem?.implicitWidth ?? viewport.width
                    implicitHeight: currentItem?.implicitHeight ?? 0
                    initialItem: BluetoothPanel { handle: root.menuHandle }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: viewport.contentHeight > viewport.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }
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
        id: pageHeader
        required property string title
        property string subtitle: ""
        spacing: 8

        RippleButton {
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            releaseAction: () => stackView.pop()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: 20
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: pageHeader.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                visible: pageHeader.subtitle !== ""
                Layout.fillWidth: true
                text: pageHeader.subtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    component BluetoothPanel: ColumnLayout {
        id: panel
        required property QsMenuHandle handle
        property bool shown: false

        readonly property var grouped: {
            const result = {
                power: null,
                discoverable: null,
                disconnects: [],
                profiles: [],
                send: null,
                reconnect: null,
                audioInput: null,
                manage: [],
                more: [],
                all: []
            }
            const entries = menuOpener.children.values
            for (let i = 0; i < entries.length; i++) {
                const entry = entries[i]
                if (entry.isSeparator)
                    continue
                result.all.push(entry)
                const label = root.normalLabel(entry.text)
                if (label.startsWith("Turn Bluetooth Off") || label.startsWith("Turn Bluetooth On"))
                    result.power = entry
                else if (label.startsWith("Make Discoverable") || label.startsWith("Make Undiscoverable"))
                    result.discoverable = entry
                else if (label.startsWith("Disconnect "))
                    result.disconnects.push(entry)
                else if (label.startsWith("Audio Profiles for "))
                    result.profiles.push(entry)
                else if (label.startsWith("Send Files"))
                    result.send = entry
                else if (label.startsWith("Reconnect to"))
                    result.reconnect = entry
                else if (label.startsWith("Audio and input profiles on "))
                    result.audioInput = entry
                else if (/^(Devices|Adapters|Local Services)(?:…)?$/.test(label))
                    result.manage.push(entry)
                else
                    result.more.push(entry)
            }
            return result
        }

        readonly property bool semanticReady: grouped.power !== null
            && (grouped.disconnects.length > 0 || grouped.send !== null
                || grouped.manage.length > 0)

        readonly property var connectedDevices: {
            const usedProfiles = []
            const devices = []
            for (const disconnect of grouped.disconnects) {
                const key = root.normalizedDevice(disconnect.text, "Disconnect ")
                let profile = null
                for (let i = 0; i < grouped.profiles.length; i++) {
                    if (usedProfiles.includes(i))
                        continue
                    const candidate = grouped.profiles[i]
                    if (root.normalizedDevice(candidate.text, "Audio Profiles for ") === key) {
                        profile = candidate
                        usedProfiles.push(i)
                        break
                    }
                }
                devices.push({
                    name: root.deviceName(disconnect.text, "Disconnect "),
                    disconnect,
                    profile
                })
            }
            return devices
        }

        readonly property var quickActions: {
            const result = []
            if (grouped.send)
                result.push(grouped.send)
            if (grouped.reconnect)
                result.push(grouped.reconnect)
            if (grouped.audioInput)
                result.push(grouped.audioInput)
            return result
        }

        readonly property var moreEntries: {
            if (!semanticReady)
                return grouped.all
            const result = grouped.more.slice()
            for (const profile of grouped.profiles) {
                if (!connectedDevices.some(device => device.profile === profile))
                    result.push(profile)
            }
            return result
        }

        readonly property bool bluetoothOn: grouped.power
            ? root.normalLabel(grouped.power.text).startsWith("Turn Bluetooth Off") : false
        readonly property string deviceSummary: {
            if (!semanticReady)
                return Translation.tr("Blueman applet controls")
            if (connectedDevices.length === 0)
                return bluetoothOn ? Translation.tr("No connected devices")
                    : Translation.tr("Bluetooth is off")
            return connectedDevices.map(device => device.name).join(" · ")
        }

        implicitWidth: root.panelWidth - 32
        spacing: 12
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false

        QsMenuOpener {
            id: menuOpener
            menu: panel.handle
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                text: panel.bluetoothOn ? "bluetooth_connected" : "bluetooth_disabled"
                iconSize: Appearance.font.pixelSize.huge
                color: panel.bluetoothOn ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnSurfaceVariant
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Bluetooth")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: panel.deviceSummary
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
            StyledText {
                visible: panel.semanticReady
                text: panel.bluetoothOn ? Translation.tr("On") : Translation.tr("Off")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: panel.bluetoothOn ? Appearance.colors.colPrimary
                    : Appearance.colors.colOnSurfaceVariant
            }
        }

        SectionLabel {
            visible: panel.semanticReady
            text: Translation.tr("Controls")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: panel.semanticReady

            Loader {
                Layout.fillWidth: true
                active: panel.grouped.power !== null
                visible: active
                sourceComponent: AppletMenuEntry {
                    menuEntry: panel.grouped.power
                    semanticStyleId: "blueman"
                    presentation: "toggle"
                    labelOverride: Translation.tr("Bluetooth")
                    iconOverride: "bluetooth"
                    stretch: true
                    dismissAfterTrigger: false
                    onDismiss: root.close()
                    onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
                }
            }
            Loader {
                Layout.fillWidth: true
                active: panel.grouped.discoverable !== null
                visible: active
                sourceComponent: AppletMenuEntry {
                    menuEntry: panel.grouped.discoverable
                    semanticStyleId: "blueman"
                    presentation: "toggle"
                    labelOverride: Translation.tr("Discoverable")
                    iconOverride: "bluetooth_searching"
                    stretch: true
                    dismissAfterTrigger: false
                    onDismiss: root.close()
                    onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: panel.semanticReady && panel.connectedDevices.length > 0

            SectionLabel { text: Translation.tr("Connected devices") }

            Repeater {
                model: panel.connectedDevices
                delegate: RowLayout {
                    id: deviceRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "headphones"
                        iconSize: 20
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: deviceRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            text: Translation.tr("Connected")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                    Loader {
                        active: deviceRow.modelData.profile !== null
                        visible: active
                        sourceComponent: AppletMenuEntry {
                            menuEntry: deviceRow.modelData.profile
                            semanticStyleId: "blueman"
                            presentation: "compact"
                            labelOverride: Translation.tr("Profiles")
                            iconOverride: "tune"
                            onDismiss: root.close()
                            onOpenSubmenu: (handle, title) => root.openSubmenu(handle,
                                Translation.tr("Audio profiles for %1").arg(deviceRow.modelData.name))
                        }
                    }
                    AppletMenuEntry {
                        menuEntry: deviceRow.modelData.disconnect
                        semanticStyleId: "blueman"
                        presentation: "compact"
                        labelOverride: Translation.tr("Disconnect")
                        iconOverride: "link_off"
                        onDismiss: root.close()
                        onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: panel.semanticReady && panel.quickActions.length > 0

            SectionLabel { text: Translation.tr("Quick actions") }

            Repeater {
                model: panel.quickActions
                delegate: AppletMenuEntry {
                    required property QsMenuEntry modelData
                    menuEntry: modelData
                    semanticStyleId: "blueman"
                    presentation: "row"
                    stretch: true
                    onDismiss: root.close()
                    onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
                }
            }
        }

        Separator {
            visible: panel.semanticReady
                && (panel.grouped.manage.length > 0 || panel.moreEntries.length > 0)
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: panel.semanticReady && panel.grouped.manage.length > 0

            SectionLabel { text: Translation.tr("Manage") }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: panel.grouped.manage
                    delegate: AppletMenuEntry {
                        required property QsMenuEntry modelData
                        menuEntry: modelData
                        semanticStyleId: "blueman"
                        presentation: "action"
                        stretch: true
                        onDismiss: root.close()
                        onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
                    }
                }
            }
        }

        RippleButton {
            visible: panel.moreEntries.length > 0
            Layout.fillWidth: true
            implicitHeight: 36
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            releaseAction: () => stackView.push(morePageComponent.createObject(null, {
                entries: panel.moreEntries,
                fallbackMode: !panel.semanticReady
            }))

            contentItem: RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 6

                MaterialSymbol {
                    text: "more_horiz"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: panel.semanticReady ? Translation.tr("More")
                        : Translation.tr("Applet controls")
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colOnSecondaryContainer
                }
                MaterialSymbol {
                    text: "chevron_right"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    component MorePage: ColumnLayout {
        id: morePage
        required property var entries
        property bool fallbackMode: false
        property bool shown: false

        implicitWidth: root.panelWidth - 32
        spacing: 10
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        PageHeader {
            Layout.fillWidth: true
            title: morePage.fallbackMode ? Translation.tr("Applet controls")
                : Translation.tr("More")
            subtitle: Translation.tr("Blueman applet actions")
        }
        Separator {}

        Repeater {
            model: morePage.entries
            delegate: AppletMenuEntry {
                required property QsMenuEntry modelData
                menuEntry: modelData
                semanticStyleId: "blueman"
                presentation: root.normalLabel(modelData.text) === "Help"
                    || root.normalLabel(modelData.text) === "Exit" ? "quiet" : "row"
                stretch: true
                onDismiss: root.close()
                onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
            }
        }
    }

    component SubMenuPage: ColumnLayout {
        id: subPage
        required property QsMenuHandle handle
        required property string pageTitle
        property bool shown: false

        implicitWidth: root.panelWidth - 32
        spacing: 10
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: subMenuOpener
            menu: subPage.handle
        }

        PageHeader {
            Layout.fillWidth: true
            title: subPage.pageTitle
        }
        Separator {}

        Repeater {
            model: subMenuOpener.children
            delegate: AppletMenuEntry {
                required property QsMenuEntry modelData
                menuEntry: modelData
                semanticStyleId: "blueman"
                presentation: "row"
                stretch: true
                onDismiss: root.close()
                onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
            }
        }
    }

    Component { id: morePageComponent; MorePage {} }
    Component { id: subMenuComponent; SubMenuPage {} }
}
