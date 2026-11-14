import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.androlink_status
import "StatusLogic.js" as Logic

/*
 * Panel opened from the bar capsule: the phone's name and connection state,
 * battery, route, background helper and unread count, a camera-in-use row
 * with a stop action, and the androlink CLI actions. With several phones a
 * row of chips picks which one the details and actions apply to.
 */
ColumnLayout {
    id: root

    // PhoneStatus reader of the owning bar entry.
    required property var reader
    // Seconds before a stuck action is stopped (module option).
    property int actionTimeoutSecs: 15
    // Low-battery threshold (module option); colours the battery value.
    property int lowThreshold: 20
    // Bumped by the bar entry each time the panel reopens.
    property int openCount: 0
    onOpenCountChanged: root.reset()

    readonly property var record: root.reader.record
    readonly property var phones: root.record.phones
    readonly property bool appRunning: Logic.appRunning(root.record)
    readonly property bool stale: root.record.state === "stale"
    // StatusLogic.phoneKey of the phone the user picked ("" follows the
    // primary phone). A key, not an index, so phones connecting or leaving
    // while the panel is open never move the pick to another phone.
    property string pickedKey: ""
    readonly property int selectedIndex: {
        const picked = Logic.indexOfKey(root.record, root.pickedKey);
        return picked >= 0 ? picked : Logic.primaryIndex(root.record);
    }
    // Always null or a phone of the current record, never undefined.
    readonly property var phone: root.phones[root.selectedIndex] ?? null
    // Device actions need a live record, a connected phone, and a phone the
    // CLI can be told (with several phones, a safe id).
    readonly property bool deviceActionsReady: root.appRunning && !root.stale && root.phone !== null && root.phone.connected
        && Logic.canTarget(root.phone, root.phones.length)

    spacing: 10

    // Result line under the actions: an error, or a short confirmation.
    property string message: ""
    property bool messageIsError: false

    // Back to the primary phone and no stale message each time it opens.
    function reset() {
        root.pickedKey = "";
        root.message = "";
    }

    function pick(index) {
        root.pickedKey = Logic.phoneKey(root.phones[index] ?? null, index);
        root.message = "";
    }

    function phoneLabel(phone) {
        return phone && phone.name !== "" ? phone.name : Translation.tr("Phone");
    }

    function statusLine() {
        if (root.stale)
            return Translation.tr("androlink isn't responding");
        if (!root.phone)
            return "";
        if (!root.phone.connected)
            return Translation.tr("Not connected");
        switch (root.phone.route) {
        case "lan":
            return Translation.tr("Connected over LAN");
        case "tailscale":
            return Translation.tr("Connected over Tailscale");
        case "other":
            return Translation.tr("Connected over another network");
        default:
            return Translation.tr("Connected to this PC");
        }
    }

    function routeLabel(route) {
        switch (route) {
        case "lan":
            return Translation.tr("LAN");
        case "tailscale":
            return "Tailscale";
        case "other":
            return Translation.tr("Other");
        default:
            return "—";
        }
    }

    function routeIcon(route) {
        switch (route) {
        case "lan":
            return "lan";
        case "tailscale":
            return "vpn_lock";
        case "other":
            return "public";
        default:
            return "link_off";
        }
    }

    function helperLabel(helper) {
        switch (helper) {
        case "running":
            return Translation.tr("Running");
        case "stopped":
            return Translation.tr("Stopped");
        case "not_set_up":
            return Translation.tr("Not set up");
        default:
            return "—";
        }
    }

    function batteryLabel(battery) {
        if (!battery)
            return "—";
        const level = `${battery.level}%`;
        return battery.charging ? Translation.tr("%1 · charging").arg(level) : level;
    }

    function outcomeText(outcome, code) {
        switch (outcome) {
        case "notRunning":
            return Translation.tr("androlink isn't running. Open it and try again.");
        case "noPhone":
            return Translation.tr("Couldn't find this phone. Check that it's connected.");
        case "missingCli":
            return Translation.tr("Can't run androlink. Check that it's installed.");
        case "timeout":
            return Translation.tr("androlink didn't answer in time.");
        case "failed":
            return Translation.tr("That didn't work (code %1).").arg(code);
        default:
            return "";
        }
    }

    function run(flag) {
        const argv = Logic.actionArgs(flag, root.phone, root.phones.length);
        if (!argv)
            return;
        root.message = "";
        runner.run(flag, argv);
    }

    CommandRunner {
        id: runner
        timeoutSecs: root.actionTimeoutSecs
        onFinished: (flag, outcome) => {
            root.messageIsError = outcome !== "";
            if (outcome !== "")
                root.message = root.outcomeText(outcome, runner.lastExitCode);
            else if (flag === "--send-clipboard")
                root.message = Translation.tr("Sending your clipboard to the phone.");
            else
                root.message = "";
        }
    }

    component DetailRow: RowLayout {
        id: detailRow
        property string iconName
        property string label
        property string value
        property color valueColor: Appearance.colors.colOnLayer1
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: detailRow.iconName
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            text: detailRow.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
        }
        StyledText {
            text: detailRow.value
            textFormat: Text.PlainText
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            color: detailRow.valueColor
        }
    }

    component ActionButton: RippleButton {
        id: actionButton
        property string iconName
        property string label
        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: Appearance.rounding.small
        // Tonal surface one step above the panel (colLayer2 equals the
        // panel's own surface in ii themes, which would hide the button).
        colBackground: Appearance.colors.colSurfaceContainerHighest
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
        colRipple: Appearance.colors.colSurfaceContainerHighestActive
        Accessible.name: actionButton.label

        contentItem: RowLayout {
            spacing: 8
            MaterialSymbol {
                Layout.leftMargin: 4
                text: actionButton.iconName
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: actionButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }
        }
    }

    // Phone picker, only with several phones.
    Flow {
        visible: root.appRunning && root.phones.length > 1
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.appRunning ? root.phones.length : 0

            RippleButton {
                id: chip
                required property int index
                readonly property var chipPhone: root.phones[chip.index]
                implicitHeight: 30
                leftPadding: 12
                rightPadding: 12
                buttonRadius: Appearance.rounding.full
                toggled: chip.index === root.selectedIndex
                colBackground: Appearance.colors.colSurfaceContainerHighest
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.pick(chip.index)
                contentItem: StyledText {
                    text: root.phoneLabel(chip.chipPhone)
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: chip.toggled ? Appearance.colors.colOnPrimary : (chip.chipPhone && chip.chipPhone.connected ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext)
                }
            }
        }
    }

    // Header: icon, name, connection line.
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        MaterialSymbol {
            text: !root.appRunning ? "mobile_off" : root.stale ? "sync_problem" : "smartphone"
            fill: root.phone && root.phone.connected && !root.stale ? 1 : 0
            iconSize: Appearance.font.pixelSize.hugeass + 6
            color: root.appRunning && root.phone && root.phone.connected && !root.stale ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: !root.appRunning ? Translation.tr("androlink isn't running")
                    : root.phone ? root.phoneLabel(root.phone)
                    : Translation.tr("No phone paired yet")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: text !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: !root.appRunning ? (root.record.state === "invalid"
                        ? Translation.tr("Can't read androlink's status file. Restarting androlink usually fixes it.")
                        : Translation.tr("Open androlink to see your phone here."))
                    : root.phone ? root.statusLine()
                    : root.stale ? root.statusLine()
                    : Translation.tr("Pair a phone in androlink to see it here.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.stale ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }
    }

    // Camera in use: a privacy indicator with its stop action.
    Rectangle {
        visible: root.appRunning && root.phone !== null && root.phone.webcam
        Layout.fillWidth: true
        implicitHeight: cameraRow.implicitHeight + 12
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer

        RowLayout {
            id: cameraRow
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 8

            MaterialSymbol {
                text: "videocam"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnErrorContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Camera in use")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnErrorContainer
            }
            RippleButton {
                implicitHeight: 30
                leftPadding: 12
                rightPadding: 12
                buttonRadius: Appearance.rounding.full
                enabled: !runner.busy
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colErrorActive
                onClicked: root.run("--webcam-stop")
                contentItem: StyledText {
                    text: Translation.tr("Stop")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnError
                }
            }
        }
    }

    // Details of the selected phone.
    ColumnLayout {
        visible: root.appRunning && root.phone !== null
        Layout.fillWidth: true
        spacing: 6

        DetailRow {
            iconName: root.phone && root.phone.battery && root.phone.battery.charging ? "battery_charging_full" : "battery_full"
            label: Translation.tr("Battery level")
            value: root.batteryLabel(root.phone ? root.phone.battery : null)
            valueColor: root.phone && root.phone.battery && !root.phone.battery.charging && root.phone.battery.level <= root.lowThreshold
                ? Appearance.colors.colError : Appearance.colors.colOnLayer1
        }
        DetailRow {
            iconName: root.routeIcon(root.phone ? root.phone.route : null)
            label: Translation.tr("Connection")
            value: root.phone && root.phone.connected ? root.routeLabel(root.phone.route) : Translation.tr("Not connected")
        }
        DetailRow {
            iconName: "smart_toy"
            label: Translation.tr("Background helper")
            value: root.helperLabel(root.phone ? root.phone.helper : null)
            valueColor: root.phone && root.phone.helper === "stopped" ? Appearance.colors.colError : Appearance.colors.colOnLayer1
        }
        DetailRow {
            iconName: "notifications"
            label: Translation.tr("Unread notifications")
            value: root.phone ? String(root.phone.unread) : "0"
        }
    }

    // Actions.
    GridLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        columns: 2
        columnSpacing: 6
        rowSpacing: 6

        ActionButton {
            visible: root.appRunning && root.phone !== null
            enabled: root.deviceActionsReady && !runner.busy
            iconName: root.phone && root.phone.ringing ? "notifications_off" : "ring_volume"
            label: root.phone && root.phone.ringing ? Translation.tr("Stop ringing") : Translation.tr("Ring phone")
            onClicked: root.run(root.phone && root.phone.ringing ? "--ring-stop" : "--ring")
        }
        ActionButton {
            visible: root.appRunning && root.phone !== null
            enabled: root.deviceActionsReady && !runner.busy
            iconName: "content_paste_go"
            label: Translation.tr("Send clipboard")
            onClicked: root.run("--send-clipboard")
        }
        ActionButton {
            visible: root.appRunning && root.phone !== null
            enabled: root.deviceActionsReady && !runner.busy
            iconName: "desktop_windows"
            label: Translation.tr("Open DeX")
            onClicked: root.run("--dex")
        }
        ActionButton {
            Layout.columnSpan: root.appRunning && root.phone !== null ? 1 : 2
            iconName: "open_in_new"
            label: Translation.tr("Open androlink")
            onClicked: root.run("")
        }
    }

    // Result of the last action.
    RowLayout {
        visible: root.message !== ""
        Layout.fillWidth: true
        spacing: 6

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: root.messageIsError ? "error" : "check_circle"
            iconSize: Appearance.font.pixelSize.normal
            color: root.messageIsError ? Appearance.colors.colError : Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.message
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.messageIsError ? Appearance.colors.colError : Appearance.colors.colSubtext
        }
    }
}
