// IIMP bar slot — installed and owned by iimod. DO NOT EDIT (recomposed on reapply).
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/*
 * Host slot for bar modules in the horizontal bar, with Bartender-style
 * pages. Every enabled bar module is instantiated once (per bar) inside the
 * row of its page; pages are stacked in place and cross-fade, so module
 * state survives switching. The slot reserves the width of its widest page,
 * so neither the page button nor the stock items beside it move when the
 * page changes.
 *
 * Width (never Loader.visible) follows item.visible for each module, because
 * item.visible is EFFECTIVE visibility and would read false forever once the
 * Loader itself were hidden; non-current pages therefore stay visible and
 * use opacity 0 plus enabled: false instead.
 */
Item {
    id: root

    // Enabled bar module ids, in bar order (first id is rightmost).
    property var ids: []
    // JSON-encoded map of module id -> page index (0 = main page).
    property string pagesJson: "{}"
    // Pointer currently over the bar's right section.
    property bool barHovered: false
    // Index into pageList of the page shown; 0 is the main page.
    property int pageIndex: 0

    readonly property var pageMap: {
        try {
            const parsed = JSON.parse(root.pagesJson || "{}");
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
        } catch (error) {
            return {};
        }
    }
    function pageOf(id) {
        const page = Number(root.pageMap[id]);
        return Number.isInteger(page) && page > 0 ? page : 0;
    }
    // Distinct pages in use, ascending; the cycle never shows an empty page.
    readonly property var pageList: Array.from(new Set((root.ids ?? []).map(id => root.pageOf(id)))).sort((a, b) => a - b)
    readonly property int pageCount: root.pageList.length
    readonly property bool paged: root.pageCount > 1
    readonly property int currentPage: root.pageList[Math.min(root.pageIndex, Math.max(0, root.pageCount - 1))] ?? 0
    // Natural width of the widest page; recomputed imperatively because a
    // binding over Repeater.itemAt() would not notice width changes.
    property real pagesWidth: 0

    visible: (root.ids ?? []).length > 0
    implicitWidth: (root.paged ? pager.implicitWidth + layout.spacing : 0) + root.pagesWidth
    implicitHeight: 24

    onPageCountChanged: if (root.pageIndex >= root.pageCount)
        root.pageIndex = 0
    onBarHoveredChanged: {
        if (root.barHovered)
            returnTimer.stop();
        else if (root.pageIndex !== 0)
            returnTimer.restart();
    }

    function nextPage() {
        root.pageIndex = root.pageCount > 0 ? (root.pageIndex + 1) % root.pageCount : 0;
    }

    function recomputeWidth() {
        let widest = 0;
        for (let i = 0; i < pagesRepeater.count; i++) {
            const page = pagesRepeater.itemAt(i);
            if (page)
                widest = Math.max(widest, page.implicitWidth);
        }
        root.pagesWidth = widest;
    }

    Timer {
        id: returnTimer
        interval: 5000
        onTriggered: if (!root.barHovered)
            root.pageIndex = 0
    }

    Row {
        id: layout
        anchors.fill: parent
        layoutDirection: Qt.RightToLeft
        spacing: 9

        RippleButton {
            id: pager
            visible: root.paged
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 24
            implicitWidth: Math.max(24, pagerLabel.implicitWidth + 12)
            toggled: root.pageIndex !== 0
            downAction: () => root.nextPage()
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive

            contentItem: StyledText {
                id: pagerLabel
                anchors.centerIn: parent
                text: `${root.pageIndex + 1}/${root.pageCount}`
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.pageIndex !== 0 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }
        }

        Item {
            id: pagesBox
            width: root.pagesWidth
            height: parent.height

            Repeater {
                id: pagesRepeater
                model: root.pageList

                delegate: Row {
                    id: pageRow
                    required property int modelData
                    readonly property bool current: modelData === root.currentPage

                    anchors.right: parent.right
                    height: parent.height
                    layoutDirection: Qt.RightToLeft
                    spacing: 9
                    opacity: current ? 1 : 0
                    enabled: current
                    // Slight rise on entry, drop on exit, with the fade.
                    anchors.verticalCenterOffset: current ? 0 : 6
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on anchors.verticalCenterOffset {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    onImplicitWidthChanged: root.recomputeWidth()
                    Component.onCompleted: root.recomputeWidth()
                    Component.onDestruction: Qt.callLater(root.recomputeWidth)

                    Repeater {
                        model: (root.ids ?? []).filter(id => root.pageOf(id) === pageRow.modelData)
                        delegate: Loader {
                            required property string modelData
                            readonly property bool shown: item !== null && item.visible
                            anchors.verticalCenter: parent?.verticalCenter
                            width: shown ? item.implicitWidth : 0
                            source: Quickshell.shellPath(`mod/${modelData}/bar.qml`)
                            onStatusChanged: if (status === Loader.Error)
                                console.warn(`[iimp] bar module failed: ${modelData}`)
                        }
                    }
                }
            }
        }
    }
}
