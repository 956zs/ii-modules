pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

PopupWindow {
    id: root

    required property QsMenuHandle menuHandle

    readonly property real outerMargin: Appearance.sizes.elevationMargin
    readonly property real panelWidth: 360
    readonly property real sourceScreenHeight: root.anchor.window?.screen?.height ?? 900
    readonly property real maxContentHeight: Math.max(220, Math.min(620,
        sourceScreenHeight - Appearance.sizes.barHeight - outerMargin * 2 - 24))
    readonly property real targetPanelHeight: Math.min(
        (stackView.currentItem?.implicitHeight ?? 0) + panelSurface.padding * 2,
        root.maxContentHeight + panelSurface.padding * 2)
    property real settledPanelHeight: 1
    property bool layoutReady: false
    property bool pendingOpen: false
    property bool revealed: false

    signal menuClosed()
    signal menuOpened(qsWindow: var)

    color: "transparent"
    implicitWidth: panelWidth + outerMargin * 2
    implicitHeight: settledPanelHeight + outerMargin * 2
    onTargetPanelHeightChanged: settleTimer.restart()
    onVisibleChanged: {
        if (visible)
            GlobalFocusGrab.addDismissable(root)
        else
            GlobalFocusGrab.removeDismissable(root)
    }
    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            root.close()
        }
    }

    function normalizedLabel(text) {
        const source = String(text ?? "")
        let result = ""
        for (let i = 0; i < source.length; ++i) {
            if (source[i] !== "_") {
                result += source[i]
            } else if (i + 1 < source.length && source[i + 1] === "_") {
                result += "_"
                ++i
            } else if (i + 1 >= source.length) {
                result += "_"
            }
        }
        return result.replace(/\.\.\.$/, "…").trim()
    }

    function displayLabel(entry) {
        const nativeLabel = normalizedLabel(entry?.text)
        if (nativeLabel.length > 0)
            return nativeLabel
        if (entry?.hasChildren)
            return Translation.tr("Network options")
        if (entry?.buttonType === QsMenuButtonType.CheckBox)
            return Translation.tr("Network setting")
        if (entry?.buttonType === QsMenuButtonType.RadioButton)
            return Translation.tr("Network choice")
        if (entry && !entry.enabled)
            return Translation.tr("Network status")
        return Translation.tr("Network action")
    }

    function materialIcon(entry) {
        const label = normalizedLabel(entry?.text).toLocaleLowerCase()
        if (label.includes("disconnect"))
            return "link_off"
        if (label.includes("connection information") || label === "information")
            return "info"
        if (label.includes("edit") || label.includes("setting"))
            return "settings"
        if (label.includes("hidden") || label.includes("password"))
            return "wifi_lock"
        if (label.includes("vpn"))
            return "vpn_key"
        if (label.includes("ethernet") || label.includes("wired"))
            return "lan"
        if (label.includes("create") || label.includes("add"))
            return "add_link"
        if (label.includes("networking"))
            return "public"
        if (label.includes("wi-fi") || label.includes("wifi")
                || label.includes("wireless") || label.includes("network"))
            return "wifi"
        if (entry?.hasChildren)
            return "list"
        if (entry?.buttonType !== QsMenuButtonType.None)
            return "tune"
        return "network_check"
    }

    function compactEntries(values) {
        const entries = []
        for (const entry of values ?? []) {
            if (!entry)
                continue
            if (entry.isSeparator) {
                if (entries.length === 0 || entries[entries.length - 1].isSeparator)
                    continue
            }
            entries.push(entry)
        }
        if (entries.length > 0 && entries[entries.length - 1].isSeparator)
            entries.pop()
        return entries
    }

    function open() {
        if (!root.layoutReady) {
            root.pendingOpen = true
            settleTimer.restart()
            return
        }
        root.revealed = false
        root.visible = true
        Qt.callLater(() => root.revealed = true)
        root.menuOpened(root)
    }

    function close() {
        const wasVisible = root.visible
        root.pendingOpen = false
        root.revealed = false
        root.visible = false
        while (stackView.depth > 1)
            stackView.pop()
        if (wasVisible)
            root.menuClosed()
    }

    Timer {
        id: settleTimer
        interval: 50
        repeat: false
        onTriggered: {
            root.settledPanelHeight = Math.max(1, root.targetPanelHeight)
            root.layoutReady = root.settledPanelHeight > 1
            if (root.layoutReady && root.pendingOpen) {
                root.pendingOpen = false
                root.open()
            }
        }
    }

    function openSubmenu(handle, title) {
        stackView.push(menuPageComponent.createObject(null, {
            handle,
            pageTitle: title,
            isSubmenu: true
        }))
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        focus: root.visible

        Keys.onEscapePressed: root.close()
        onPressed: event => {
            if (event.button === Qt.BackButton) {
                if (stackView.depth > 1)
                    stackView.pop()
                else
                    root.close()
            } else if (event.button === Qt.RightButton && stackView.depth > 1) {
                stackView.pop()
            }
        }

        StyledRectangularShadow {
            target: panelSurface
            opacity: panelSurface.opacity
        }

        Rectangle {
            id: panelSurface

            readonly property real padding: 4

            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical || Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical || !Config.options.bar.bottom ? undefined : parent.bottom
                margins: root.outerMargin
            }
            implicitHeight: root.revealed ? root.settledPanelHeight : 1
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            opacity: root.revealed ? 1 : 0

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
                    margins: panelSurface.padding
                }
                implicitWidth: root.panelWidth - panelSurface.padding * 2
                implicitHeight: currentItem?.implicitHeight ?? 0
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}
                initialItem: MenuPage {
                    handle: root.menuHandle
                    pageTitle: Translation.tr("Wi-Fi")
                }
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation { duration: 0 }
    }

    component MenuEntry: RippleButton {
        id: entryButton

        required property QsMenuEntry menuEntry
        property bool forceSpecialInteractionColumn: false

        readonly property bool hasEntry: menuEntry !== null
        readonly property string label: root.displayLabel(menuEntry)
        readonly property bool hasNativeIcon: String(menuEntry?.icon ?? "").length > 0
        readonly property bool hasSpecialInteraction:
            menuEntry?.buttonType !== QsMenuButtonType.None
        readonly property bool selected: menuEntry?.checkState === Qt.Checked
        readonly property bool partiallySelected:
            menuEntry?.checkState === Qt.PartiallyChecked

        signal dismiss()
        signal openSubmenu(handle: QsMenuHandle, title: string)

        function selectionIcon() {
            if (!hasEntry)
                return ""
            if (menuEntry.buttonType === QsMenuButtonType.RadioButton)
                return selected ? "radio_button_checked" : "radio_button_unchecked"
            if (partiallySelected)
                return "indeterminate_check_box"
            return selected ? "check_box" : "check_box_outline_blank"
        }

        enabled: hasEntry && !menuEntry.isSeparator && menuEntry.enabled
        opacity: hasEntry && (menuEntry.enabled || menuEntry.isSeparator) ? 1 : 0.58
        Layout.fillWidth: true
        Layout.topMargin: hasEntry && menuEntry.isSeparator ? 5 : 0
        Layout.bottomMargin: hasEntry && menuEntry.isSeparator ? 5 : 0
        implicitHeight: !hasEntry ? 0 : menuEntry.isSeparator ? 1 : 40
        horizontalPadding: 10
        buttonRadius: Appearance.rounding.small
        colBackground: hasEntry && menuEntry.isSeparator
            ? Appearance.colors.colLayer0Border
            : "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        Component.onCompleted: {
            if (hasEntry && menuEntry.isSeparator)
                entryButton.buttonColor = entryButton.colBackground
        }

        releaseAction: () => {
            if (!hasEntry)
                return
            if (menuEntry.hasChildren) {
                entryButton.openSubmenu(menuEntry, entryButton.label)
                return
            }
            menuEntry.triggered()
            entryButton.dismiss()
        }
        altAction: event => event.accepted = false

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: entryButton.horizontalPadding
                rightMargin: entryButton.horizontalPadding
            }
            spacing: 10
            visible: entryButton.hasEntry && !entryButton.menuEntry.isSeparator

            Item {
                visible: entryButton.hasSpecialInteraction
                    || entryButton.forceSpecialInteractionColumn
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: entryButton.hasSpecialInteraction
                    text: entryButton.selectionIcon()
                    iconSize: 20
                    color: entryButton.selected || entryButton.partiallySelected
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnSurfaceVariant
                }
            }

            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22

                IconImage {
                    anchors.centerIn: parent
                    visible: entryButton.hasNativeIcon
                    asynchronous: true
                    source: entryButton.menuEntry?.icon ?? ""
                    implicitSize: 21
                    mipmap: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !entryButton.hasNativeIcon
                    text: root.materialIcon(entryButton.menuEntry)
                    iconSize: 21
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: entryButton.label
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnSurface
            }

            MaterialSymbol {
                visible: entryButton.menuEntry?.hasChildren ?? false
                text: "chevron_right"
                iconSize: 20
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    component MenuPage: Item {
        id: page

        required property QsMenuHandle handle
        required property string pageTitle
        property bool isSubmenu: false
        property bool shown: false

        readonly property var entries: root.compactEntries(menuOpener.children.values)
        readonly property bool specialInteractionColumnNeeded: entries.some(entry =>
            !entry.isSeparator && entry.buttonType !== QsMenuButtonType.None)

        implicitWidth: root.panelWidth - panelSurface.padding * 2
        implicitHeight: Math.min(pageColumn.implicitHeight, root.maxContentHeight)
        opacity: shown ? 1 : 0

        QsMenuOpener {
            id: menuOpener
            menu: page.handle
        }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Flickable {
            id: viewport

            anchors.fill: parent
            contentWidth: width
            contentHeight: pageColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: pageColumn

                width: viewport.width
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    spacing: 8

                    RippleButton {
                        visible: page.isSubmenu
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

                    MaterialSymbol {
                        visible: !page.isSubmenu
                        text: "wifi"
                        iconSize: 28
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: page.pageTitle
                        textFormat: Text.PlainText
                        font.weight: Font.DemiBold
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurface
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.bottomMargin: 4
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }

                Repeater {
                    model: page.entries
                    delegate: MenuEntry {
                        required property QsMenuEntry modelData

                        menuEntry: modelData
                        forceSpecialInteractionColumn: page.specialInteractionColumnNeeded
                        onDismiss: root.close()
                        onOpenSubmenu: (handle, title) => root.openSubmenu(handle, title)
                    }
                }

                StyledText {
                    visible: page.entries.length === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 12
                    Layout.bottomMargin: 12
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("No network actions available")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: pageColumn.implicitHeight > viewport.height
                    ? ScrollBar.AsNeeded
                    : ScrollBar.AlwaysOff
            }
        }
    }

    Component {
        id: menuPageComponent
        MenuPage {}
    }
}
