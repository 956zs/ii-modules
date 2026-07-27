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
    property real popupBackgroundMargin: 0
    readonly property real panelWidth: 340
    readonly property real sourceScreenHeight: root.anchor.window && root.anchor.window.screen
        ? root.anchor.window.screen.height
        : 900
    readonly property real maxContentHeight: Math.max(220, Math.min(
        620,
        root.sourceScreenHeight - Appearance.sizes.barHeight - root.padding * 2 - 24))

    signal menuClosed()
    signal menuOpened(qsWindow: var)

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin
    implicitWidth: root.panelWidth + root.padding * 2
    implicitHeight: stackView.implicitHeight + popupBackground.padding * 2 + root.padding * 2

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

    function normalizedLabel(text) {
        const source = String(text ?? "")
        let result = ""
        for (let i = 0; i < source.length; ++i) {
            if (source[i] !== "_") {
                result += source[i]
                continue
            }
            if (i + 1 < source.length && source[i + 1] === "_") {
                result += "_"
                ++i
            } else if (i + 1 >= source.length) {
                result += "_"
            }
        }
        return result.replace(/\.\.\.$/, "…").trim()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        focus: root.visible
        Keys.onEscapePressed: root.close()
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

            readonly property real padding: 4
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical || Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical || !Config.options.bar.bottom ? undefined : parent.bottom
                margins: root.padding
            }
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2
            color: Appearance.colors.colLayer0
            radius: Appearance.rounding.windowRounding
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

                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                implicitWidth: root.panelWidth - popupBackground.padding * 2
                implicitHeight: currentItem ? currentItem.implicitHeight : 0
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}
                initialItem: RootPage {
                    handle: root.menuHandle
                }
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation { duration: 0 }
    }

    component RootPage: Item {
        id: page

        required property QsMenuHandle handle
        readonly property var groups: page.buildGroups(menuOpener.children.values)
        readonly property var currentConnection: page.inferCurrentConnection(menuOpener.children.values)

        implicitWidth: root.panelWidth - popupBackground.padding * 2
        implicitHeight: Math.min(pageColumn.implicitHeight, root.maxContentHeight)
        opacity: shown ? 1 : 0
        property bool shown: false

        function splitSegments(values) {
            const segments = []
            let segment = []
            for (const entry of values) {
                if (entry.isSeparator) {
                    if (segment.length > 0)
                        segments.push(segment)
                    segment = []
                } else {
                    segment.push(entry)
                }
            }
            if (segment.length > 0)
                segments.push(segment)
            return segments
        }

        function segmentRole(segment, index, controlIndex, structuralVpnIndex) {
            if (segment.some(entry => entry.buttonType !== QsMenuButtonType.None))
                return "controls"

            const labels = segment.map(entry => root.normalizedLabel(entry.text).toLowerCase())
            if (labels.some(label => /(^|\s)vpn(\s|$)/.test(label)))
                return "vpn"
            if (labels.some(label => label.includes("wi-fi")
                    || label.includes("wifi")
                    || label.includes("wireless")
                    || label.includes("available network")))
                return "wifi"
            if (controlIndex >= 0 && index > controlIndex)
                return "manage"
            if (index === structuralVpnIndex)
                return "vpn"
            if (controlIndex >= 0 && index < controlIndex
                    && segment.some(entry => entry.hasChildren))
                return "wifi"
            if (controlIndex < 0 || index < controlIndex)
                return "connections"
            return "other"
        }

        function buildGroups(values) {
            const segments = page.splitSegments(values)
            const controlIndex = segments.findIndex(segment =>
                segment.some(entry => entry.buttonType !== QsMenuButtonType.None))
            const childSegmentIndices = segments
                .map((segment, index) => ({ segment, index }))
                .filter(item => item.index < controlIndex
                    && item.segment.some(entry => entry.hasChildren))
                .map(item => item.index)
            const structuralVpnIndex = childSegmentIndices.length > 1
                ? childSegmentIndices[childSegmentIndices.length - 1]
                : -1
            const buckets = {
                connections: [],
                wifi: [],
                vpn: [],
                controls: [],
                manage: [],
                other: []
            }
            for (let i = 0; i < segments.length; ++i) {
                const role = page.segmentRole(
                    segments[i], i, controlIndex, structuralVpnIndex)
                buckets[role].push(...segments[i])
            }
            return ["connections", "wifi", "vpn", "controls", "manage", "other"]
                .filter(role => buckets[role].length > 0)
                .map(role => ({ role, entries: buckets[role] }))
        }

        function inferCurrentConnection(values) {
            const segments = page.splitSegments(values)
            const controlIndex = segments.findIndex(segment =>
                segment.some(entry => entry.buttonType !== QsMenuButtonType.None))
            const childSegmentIndices = segments
                .map((segment, index) => ({ segment, index }))
                .filter(item => item.index < controlIndex
                    && item.segment.some(entry => entry.hasChildren))
                .map(item => item.index)
            const structuralVpnIndex = childSegmentIndices.length > 1
                ? childSegmentIndices[childSegmentIndices.length - 1]
                : -1

            for (let i = 0; i < segments.length; ++i) {
                const segment = segments[i]
                const role = page.segmentRole(
                    segment, i, controlIndex, structuralVpnIndex)
                if (role === "vpn" || role === "controls" || role === "manage")
                    continue
                // nm-applet places a disabled device/status label before active
                // connection rows. Command-only segments contain no such marker.
                if (!segment.some(entry => !entry.enabled
                        && !entry.hasChildren
                        && entry.buttonType === QsMenuButtonType.None))
                    continue

                const childIndex = segment.findIndex(entry => entry.hasChildren)
                const candidates = segment
                    .slice(0, childIndex >= 0 ? childIndex : segment.length)
                    .filter(entry => entry.enabled
                        && !entry.hasChildren
                        && entry.buttonType === QsMenuButtonType.None)
                if (candidates.length === 0)
                    continue

                const labels = segment.map(entry => root.normalizedLabel(entry.text).toLowerCase())
                let icon = role === "wifi" ? "signal_wifi_4_bar" : "network_check"
                if (labels.some(label => label.includes("ethernet")))
                    icon = "lan"
                else if (labels.some(label => /(^|\s)vpn(\s|$)/.test(label)))
                    icon = "vpn_key"
                return { name: root.normalizedLabel(candidates[0].text), icon }
            }
            return { name: "", icon: "signal_wifi_off" }
        }

        function sectionTitle(role) {
            if (role === "connections") return Translation.tr("Connections")
            if (role === "wifi") return Translation.tr("Wi-Fi")
            if (role === "vpn") return Translation.tr("VPN")
            if (role === "controls") return Translation.tr("Controls")
            if (role === "manage") return Translation.tr("Connection management")
            return Translation.tr("Other")
        }

        function openSubmenu(handle, title, semanticRole) {
            stackView.push(subMenuComponent.createObject(null, {
                handle,
                title,
                semanticRole
            }))
        }

        QsMenuOpener {
            id: menuOpener
            menu: page.handle
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: shown = true

        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: pageColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: pageColumn

                width: parent.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 10
                    Layout.bottomMargin: 8
                    spacing: 10

                    MaterialSymbol {
                        text: page.currentConnection.icon
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colPrimary
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            text: Translation.tr("Network")
                            font.weight: Font.DemiBold
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: page.currentConnection.name.length > 0
                                ? page.currentConnection.name
                                : Translation.tr("Not connected")
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1Inactive
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                Repeater {
                    model: page.groups
                    delegate: ColumnLayout {
                        id: group

                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            Layout.topMargin: 8
                            Layout.bottomMargin: 2
                            text: page.sectionTitle(group.modelData.role)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        Repeater {
                            model: group.modelData.entries
                            delegate: NetworkMenuEntry {
                                required property QsMenuEntry modelData
                                menuEntry: modelData
                                semanticRole: group.modelData.role
                                onDismiss: root.close()
                                onOpenSubmenu: handle => page.openSubmenu(
                                    handle,
                                    root.normalizedLabel(modelData.text),
                                    group.modelData.role)
                            }
                        }
                    }
                }
            }
        }
    }

    component SubMenuPage: Item {
        id: submenu

        required property QsMenuHandle handle
        required property string title
        required property string semanticRole
        implicitWidth: root.panelWidth - popupBackground.padding * 2
        implicitHeight: Math.min(submenuColumn.implicitHeight, root.maxContentHeight)
        opacity: shown ? 1 : 0
        property bool shown: false

        QsMenuOpener {
            id: submenuOpener
            menu: submenu.handle
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: submenuColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: submenuColumn

                width: parent.width
                spacing: 0

                RippleButton {
                    id: backButton

                    Layout.fillWidth: true
                    implicitHeight: 42
                    horizontalPadding: 10
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    colRipple: Appearance.colors.colLayer1Active
                    releaseAction: () => stackView.pop()

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: backButton.horizontalPadding
                            rightMargin: backButton.horizontalPadding
                        }
                        spacing: 10
                        MaterialSymbol {
                            text: "chevron_left"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Back")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer1Inactive
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: submenu.title
                                textFormat: Text.PlainText
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colOnSurface
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                Repeater {
                    model: submenuOpener.children
                    delegate: NetworkMenuEntry {
                        required property QsMenuEntry modelData
                        menuEntry: modelData
                        semanticRole: submenu.semanticRole
                        onDismiss: root.close()
                        onOpenSubmenu: handle => stackView.push(subMenuComponent.createObject(null, {
                            handle,
                            title: root.normalizedLabel(modelData.text),
                            semanticRole: submenu.semanticRole
                        }))
                    }
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenuPage {}
    }
}
