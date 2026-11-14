import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "ReplyLogic.js" as Logic

/*
 * Reply field shown inside a stock notification item (inserted into
 * NotificationItem.qml by this module's Tier B patch) while the live
 * Quickshell Notification exists and offers an inline reply. Enter sends,
 * Esc cancels. Restored or persisted entries never show it.
 *
 * In the popup the field takes part in two stock mechanisms patched by this
 * module: the wrapper's `iimpReplyHold` stops the popup from timing out
 * while the field has text or is being typed in, and
 * `Notifications.iimpReplyComposer` makes the popup window take the
 * keyboard (with a focus grab that a click outside clears). In the sidebar
 * the window already takes the keyboard on click.
 *
 * The reply text is never logged.
 */
Item {
    id: root

    // The ii Notif wrapper of this item (services/Notifications.qml).
    property var notif: null
    // NotificationUrgency of the item, to match the stock action buttons.
    property string urgency: ""

    // Live Quickshell Notification; null for restored entries and after the
    // sender closed it.
    readonly property var live: root.notif ? root.notif.notification : null
    readonly property bool available: Logic.canReply(root.live)
    // Loose equality on purpose: the wrapper stores the urgency as a string
    // ("2") and stock compares it to the enum the same way.
    readonly property bool critical: root.urgency == NotificationUrgency.Critical
    // Stock NotificationGroup hosting this item, found once the delegate is
    // parented (see refreshGroup).
    property var group: null
    readonly property bool inPopup: root.group !== null && root.group.popup === true

    // Typing in this field (popup: holds the keyboard).
    property bool composing: false
    readonly property bool hasText: field.text.length > 0
    // The popup must stay while the field is in use.
    readonly property bool holding: root.inPopup && root.available && (root.composing || root.hasText)
    // Brief confirmation on the send button after replying to a notification
    // that stays (resident).
    property bool justSent: false

    visible: root.available
    implicitWidth: row.implicitWidth
    implicitHeight: root.available ? row.implicitHeight : 0

    function refreshGroup() {
        if (root.group === null)
            root.group = Logic.hostGroup(root);
    }

    function startComposing() {
        if (!root.available)
            return;
        root.refreshGroup();
        root.composing = true;
        field.forceActiveFocus();
    }

    function stopComposing() {
        root.composing = false;
        if (field.activeFocus)
            field.focus = false;
    }

    function cancel() {
        field.clear();
        root.stopComposing();
    }

    function send() {
        if (field.inputMethodComposing)
            return;
        const text = Logic.replyText(field.text);
        const target = root.live;
        if (text === "" || !Logic.canReply(target))
            return;
        // Settle local state first: a non-resident notification closes
        // during sendInlineReply and takes this item with it.
        field.clear();
        root.stopComposing();
        root.justSent = true;
        sentTimer.restart();
        target.sendInlineReply(text);
    }

    onHoldingChanged: {
        if (root.notif && root.notif.iimpReplyHold !== undefined && root.inPopup)
            root.notif.iimpReplyHold = root.holding;
        if (!root.holding && Logic.timeoutAfterRelease(root.notif, root.group))
            Notifications.timeoutNotification(root.notif.notificationId);
    }

    onComposingChanged: {
        if (!root.inPopup || !root.notif || Notifications.iimpReplyComposer === undefined)
            return;
        if (root.composing)
            Notifications.iimpReplyComposer = root.notif.notificationId;
        else if (Notifications.iimpReplyComposer === root.notif.notificationId)
            Notifications.iimpReplyComposer = -1;
    }

    onAvailableChanged: {
        if (!root.available)
            root.cancel();
    }

    // Hidden (group collapsed, popup gone, screen locked): give the keyboard
    // back but keep the text.
    onVisibleChanged: {
        if (!root.visible)
            root.stopComposing();
    }

    Component.onCompleted: Qt.callLater(root.refreshGroup)
    Component.onDestruction: {
        if (root.notif && root.inPopup) {
            if (root.notif.iimpReplyHold === true)
                root.notif.iimpReplyHold = false;
            if (Notifications.iimpReplyComposer === root.notif.notificationId)
                Notifications.iimpReplyComposer = -1;
        }
    }

    // The popup's focus grab was cleared (click outside) or another field
    // took over: stop composing, keep the text.
    Connections {
        target: Notifications
        function onIimpReplyComposerChanged() {
            if (root.composing && root.inPopup && Notifications.iimpReplyComposer !== root.notif?.notificationId)
                root.stopComposing();
        }
    }

    Timer {
        id: sentTimer
        interval: 1500
        onTriggered: root.justSent = false
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 5

        TextField {
            id: field
            Layout.fillWidth: true
            implicitHeight: 34
            leftPadding: 12
            rightPadding: 12
            topPadding: 0
            bottomPadding: 0
            verticalAlignment: TextInput.AlignVCenter
            placeholderText: Logic.placeholder(root.live, Translation.tr("Reply…"))
            placeholderTextColor: Appearance.colors.colSubtext
            color: root.critical ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
            selectedTextColor: Appearance.colors.colOnSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            renderType: Text.NativeRendering
            font {
                family: Appearance.font.family.main
                pixelSize: Appearance.font.pixelSize.small
                hintingPreference: Font.PreferFullHinting
                variableAxes: Appearance.font.variableAxes.main
            }
            Accessible.name: placeholderText

            background: Rectangle {
                radius: Appearance.rounding.small
                color: root.critical ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer4
                border.width: field.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }

            onPressed: root.startComposing()
            onActiveFocusChanged: {
                if (field.activeFocus && !root.composing)
                    root.startComposing();
            }
            onAccepted: root.send()

            Keys.onEscapePressed: event => {
                root.cancel();
                event.accepted = true;
            }
            Keys.onPressed: event => {
                if (Logic.containsKey(event.key))
                    event.accepted = true;
            }
        }

        RippleButton {
            id: sendButton
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.small
            enabled: root.justSent || Logic.replyText(field.text) !== ""
            colBackground: root.critical ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer4
            colBackgroundHover: root.critical ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer4Hover
            colRipple: root.critical ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer4Active
            Accessible.name: root.justSent ? Translation.tr("Reply sent") : Translation.tr("Send reply")
            onClicked: root.send()

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                iconSize: Appearance.font.pixelSize.larger
                text: root.justSent ? "check" : "send"
                fill: 1
                color: root.critical ? Appearance.m3colors.m3onSurfaceVariant : Appearance.colors.colPrimary
            }

            StyledToolTip {
                text: Translation.tr("Send reply")
            }
        }
    }
}
