// IIMP settings page — installed and owned by iimod. DO NOT EDIT (recomposed on reapply).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/*
 * Installed-only module manager. iimod remains the enable/disable authority;
 * this page requests a transition and reloads the index projection. Switches
 * stay bound to projected state, so failed operations snap back naturally.
 */
ContentPage {
    id: root

    forceWidth: true
    baseWidth: Math.max(320, width - 40)
    bottomContentPadding: 20
    focus: true

    property var mods: []
    property string indexError: ""
    property string searchText: ""
    property string statusFilter: "all"
    property string selectedId: ""
    property bool narrowDetailOpen: false
    property var operationStates: ({})

    readonly property bool wideLayout: baseWidth >= 760
    readonly property var filteredMods: filterModules(
        mods,
        searchText,
        statusFilter,
        module => [
            localized(module.name, module.id),
            module.id ?? "",
            localized(module.description, ""),
        ].join(" "),
        id => operationFor(id).error.length > 0
    )
    readonly property var selectedModule: moduleById(selectedId)
    readonly property bool hasSelection: selectedModule !== null
    readonly property int enabledCount: mods.filter(module => module.state === "enabled").length
    readonly property int attentionCount: mods.filter(module => needsAttention(module)).length
    readonly property var filterOptions: [
        { value: "all", label: Translation.tr("All"), count: mods.length },
        { value: "enabled", label: Translation.tr("Enabled"), count: enabledCount },
        { value: "disabled", label: Translation.tr("Disabled"), count: mods.filter(module => module.state === "disabled").length },
        { value: "attention", label: Translation.tr("Needs attention"), count: attentionCount },
    ]

    function localized(dict, fallback) {
        if (!dict)
            return fallback ?? "";
        return dict[Translation.languageCode] ?? dict.en_US ?? fallback ?? "";
    }

    function moduleById(id) {
        return root.mods.find(module => module.id === id) ?? null;
    }

    function operationFor(id) {
        return root.operationStates[id] ?? { busy: false, error: "" };
    }

    function setOperation(id, busy, error) {
        const next = Object.assign({}, root.operationStates);
        next[id] = { busy: busy, error: error ?? "" };
        root.operationStates = next;
    }

    // PURE_LOGIC_START — kept dependency-free for focused Node contracts.
    function normalizedText(value) {
        return typeof value === "string" ? value.toLocaleLowerCase() : "";
    }

    function isFlippable(module) {
        return module?.state === "enabled" || module?.state === "disabled";
    }

    function needsAttention(module, hasOperationError) {
        const operationFailed = hasOperationError ?? operationFor(module?.id).error.length > 0;
        return !!module && (!isFlippable(module) || operationFailed === true);
    }

    function filterModules(modules, query, filter, searchTextFor, hasOperationError) {
        const items = Array.isArray(modules) ? modules : [];
        const normalizedQuery = normalizedText(query).trim();
        const searchable = typeof searchTextFor === "function" ? searchTextFor : () => "";
        const operationFailed = typeof hasOperationError === "function" ? hasOperationError : () => false;

        return items.filter(module => {
            if (!module || typeof module !== "object")
                return false;
            const matchesStatus = filter === "enabled" ? module.state === "enabled"
                : filter === "disabled" ? module.state === "disabled"
                : filter === "attention" ? needsAttention(module, operationFailed(module.id))
                : true;
            return matchesStatus && (normalizedQuery === ""
                || normalizedText(searchable(module)).indexOf(normalizedQuery) !== -1);
        });
    }

    function reconcileSelectedId(modules, selectedId) {
        const items = Array.isArray(modules) ? modules.filter(module => module?.id) : [];
        if (items.length === 0)
            return "";
        return items.some(module => module.id === selectedId) ? selectedId : items[0].id;
    }

    function slotKind(slots) {
        const items = Array.isArray(slots) ? slots : [];
        const hasBar = items.indexOf("bar") !== -1;
        const hasWindow = items.indexOf("window") !== -1;
        return hasBar && hasWindow ? "both" : hasBar ? "bar" : "window";
    }
    // PURE_LOGIC_END

    function slotIcon(module) {
        const kind = slotKind(module?.slots);
        return kind === "both" ? "dashboard_customize" : kind === "bar" ? "toolbar" : "web_asset";
    }

    function slotLabel(module) {
        const kind = slotKind(module?.slots);
        if (kind === "both")
            return Translation.tr("Bar + Window");
        return kind === "bar" ? Translation.tr("Bar") : Translation.tr("Window");
    }

    function stateLabel(module) {
        if (!module)
            return "";
        if (module.state === "enabled")
            return Translation.tr("Enabled");
        if (module.state === "disabled")
            return Translation.tr("Disabled");
        if (module.state === "incompatible")
            return Translation.tr("Incompatible");
        return Translation.tr("Blocked by dependency");
    }

    function reconcileSelection() {
        root.selectedId = reconcileSelectedId(root.filteredMods, root.selectedId);
        if (root.selectedId.length === 0 && !root.wideLayout)
            root.narrowDetailOpen = false;
    }

    function selectModule(id) {
        root.selectedId = id;
        if (!root.wideLayout)
            root.narrowDetailOpen = true;
    }

    function clearFilters() {
        root.searchText = "";
        root.statusFilter = "all";
    }

    function flip(id, on) {
        if (!isFlippable(moduleById(id)) || flipProc.running)
            return;
        setOperation(id, true, "");
        flipProc.targetId = id;
        flipProc.wanted = on ? "enable" : "disable";
        flipProc.lastError = "";
        flipProc.running = true;
    }

    function barPlacement(id) {
        try {
            return JSON.parse(Config.options.iimp?.barPlacementsJson ?? "{}")[id] ?? "top";
        } catch (error) {
            return "top";
        }
    }

    function setBarPlacement(id, value) {
        let next = {};
        try {
            next = JSON.parse(Config.options.iimp?.barPlacementsJson ?? "{}");
        } catch (error) {
            next = {};
        }
        next[id] = value;
        Config.options.iimp.barPlacementsJson = JSON.stringify(next);
    }

    onFilteredModsChanged: Qt.callLater(reconcileSelection)
    onWideLayoutChanged: if (wideLayout) narrowDetailOpen = false

    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Escape)
            return;
        if (root.searchText.length > 0) {
            root.searchText = "";
            event.accepted = true;
        } else if (!root.wideLayout && root.narrowDetailOpen) {
            root.narrowDetailOpen = false;
            event.accepted = true;
        }
    }

    FileView {
        id: indexFile
        path: Directories.shellConfig + "/modules/index.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const document = JSON.parse(text());
                if (!Array.isArray(document.modules))
                    throw new Error("invalid modules projection");
                root.indexError = "";
                root.mods = document.modules;
                root.reconcileSelection();
            } catch (error) {
                root.mods = [];
                root.indexError = Translation.tr("The module index could not be read.");
            }
        }
        onLoadFailed: {
            root.mods = [];
            root.indexError = Translation.tr("The module index could not be read.");
        }
    }

    Process {
        id: flipProc
        property string targetId: ""
        property string wanted: ""
        property string lastError: ""
        command: ["sh", "-c",
            `bin=$(command -v iimod || echo "$HOME/.local/bin/iimod"); exec "$bin" "$1" "$2"`,
            "iimp-toggle", wanted, targetId]
        stderr: StdioCollector {
            id: flipStderr
            onStreamFinished: flipProc.lastError = flipStderr.text
        }
        onExited: (exitCode, exitStatus) => {
            const publicError = exitCode === 0 ? ""
                : Translation.tr("Module operation failed.") + " (" + exitCode + ")";
            root.setOperation(targetId, false, publicError);
            if (exitCode !== 0)
                console.warn(`[iimp] iimod ${wanted} ${targetId} failed (${exitCode}): ${lastError.trim()}`);
            indexFile.reload();
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            StyledText {
                Layout.fillWidth: true
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Modules")
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.title + 6
                font.variableAxes: Appearance.font.variableAxes.title
            }
            StyledText {
                color: Appearance.colors.colOnSurfaceVariant
                text: Translation.tr("%1 installed · %2 enabled").arg(root.mods.length).arg(root.enabledCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 48

            MaterialTextField {
                anchors.fill: parent
                leftPadding: 44
                rightPadding: root.searchText.length > 0 ? 44 : 14
                placeholderText: Translation.tr("Search modules…")
                text: root.searchText
                wrapMode: TextEdit.NoWrap
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.searchText = text
                Accessible.name: Translation.tr("Search modules")
            }
            MaterialSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "search"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            RippleButton {
                visible: root.searchText.length > 0
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                onClicked: root.searchText = ""
                Accessible.name: Translation.tr("Clear search")
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledToolTip { text: Translation.tr("Clear search") }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.filterOptions
                delegate: RippleButton {
                    required property var modelData
                    implicitHeight: 38
                    horizontalPadding: 12
                    buttonRadius: Appearance.rounding.full
                    toggled: root.statusFilter === modelData.value
                    onClicked: root.statusFilter = modelData.value
                    Accessible.name: modelData.label + " " + modelData.count
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.label + "  " + modelData.count
                        color: root.statusFilter === modelData.value
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        RowLayout {
            id: workspace
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(360, root.height - 195)
            spacing: 12

            Rectangle {
                id: listPane
                visible: root.wideLayout || !root.narrowDetailOpen
                Layout.fillWidth: !root.wideLayout
                Layout.fillHeight: true
                Layout.preferredWidth: root.wideLayout ? Math.max(280, workspace.width * 0.38) : workspace.width
                Layout.maximumWidth: root.wideLayout ? Math.max(280, workspace.width * 0.38) : workspace.width
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                clip: true

                ListView {
                    id: moduleList
                    anchors.fill: parent
                    anchors.margins: 6
                    visible: root.filteredMods.length > 0
                    model: root.filteredMods
                    spacing: 2
                    clip: true
                    reuseItems: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: moduleRow
                        required property var modelData
                        readonly property bool moduleOn: modelData.state === "enabled"
                        readonly property bool flippable: root.isFlippable(modelData)
                        readonly property var operation: root.operationFor(modelData.id)
                        width: moduleList.width
                        height: root.wideLayout ? 76 : 88
                        radius: Appearance.rounding.small
                        color: root.selectedId === modelData.id ? Appearance.colors.colSecondaryContainer : "transparent"
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                        RippleButton {
                            anchors.fill: parent
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            colRipple: Appearance.colors.colLayer1Active
                            onClicked: root.selectModule(moduleRow.modelData.id)
                            Accessible.name: root.localized(moduleRow.modelData.name, moduleRow.modelData.id)

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 62
                                spacing: 10

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: 3
                                    text: root.slotIcon(moduleRow.modelData)
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: root.selectedId === moduleRow.modelData.id
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnSurfaceVariant
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: root.localized(moduleRow.modelData.name, moduleRow.modelData.id)
                                            font.weight: Font.DemiBold
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            color: root.selectedId === moduleRow.modelData.id
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnLayer1
                                        }
                                        MaterialSymbol {
                                            visible: moduleRow.modelData.tierB === true
                                            text: "warning"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3error
                                        }
                                        StyledText {
                                            visible: moduleRow.modelData.tierB === true
                                            text: Translation.tr("Patched")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.m3colors.m3error
                                        }
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: text.length > 0
                                        text: root.localized(moduleRow.modelData.description, "")
                                        color: Appearance.colors.colOnSurfaceVariant
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: root.wideLayout ? 1 : 2
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4
                                        StyledText {
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                            text: "v" + moduleRow.modelData.version + " · "
                                                + root.slotLabel(moduleRow.modelData) + " · "
                                                + root.stateLabel(moduleRow.modelData)
                                            color: moduleRow.flippable
                                                ? Appearance.colors.colOnLayer1Inactive
                                                : Appearance.m3colors.m3error
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                        }
                                        MaterialSymbol {
                                            visible: !moduleRow.flippable || moduleRow.operation.error.length > 0
                                            text: "error"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.m3colors.m3error
                                        }
                                        StyledText {
                                            visible: !moduleRow.flippable
                                            text: root.stateLabel(moduleRow.modelData)
                                            color: Appearance.m3colors.m3error
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 50
                            height: 44
                            z: 2
                            StyledSwitch {
                                anchors.centerIn: parent
                                scale: 0.85
                                enabled: moduleRow.flippable && !moduleRow.operation.busy && !flipProc.running
                                checked: moduleRow.moduleOn
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: moduleRow.flippable && !moduleRow.operation.busy && !flipProc.running
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: root.flip(moduleRow.modelData.id, !moduleRow.moduleOn)
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: Translation.tr("Enable %1").arg(root.localized(moduleRow.modelData.name, moduleRow.modelData.id))
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: moduleRow.operation.busy
                                text: "progress_activity"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                                RotationAnimation on rotation {
                                    running: moduleRow.operation.busy
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 900
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 340)
                    visible: root.filteredMods.length === 0
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.mods.length === 0 ? "extension_off" : "search_off"
                        iconSize: 42
                        color: root.indexError.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.mods.length === 0 ? Translation.tr("No modules installed") : Translation.tr("No matching modules")
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.indexError.length > 0 ? root.indexError
                            : root.mods.length === 0 ? Translation.tr("Install with: iimod install <package>")
                            : Translation.tr("Try another search or reset the status filter.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: root.mods.length === 0 && root.indexError.length === 0
                            ? Appearance.font.family.monospace : Appearance.font.family.main
                        color: root.indexError.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnSurfaceVariant
                    }
                    RippleButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.mods.length > 0
                        implicitHeight: 40
                        buttonText: Translation.tr("Clear search and filters")
                        onClicked: root.clearFilters()
                    }
                }
            }

            Rectangle {
                id: detailPane
                visible: root.wideLayout || root.narrowDetailOpen
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                clip: true

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 300)
                    visible: !root.hasSelection
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "extension"
                        iconSize: 38
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Select a module to view details")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }

                Flickable {
                    id: detailFlick
                    anchors.fill: parent
                    anchors.margins: 16
                    visible: root.hasSelection
                    contentWidth: width
                    contentHeight: detailColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: detailColumn
                        width: detailFlick.width
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            visible: !root.wideLayout
                            spacing: 6
                            RippleButton {
                                implicitWidth: 44
                                implicitHeight: 44
                                buttonRadius: Appearance.rounding.full
                                onClicked: root.narrowDetailOpen = false
                                Accessible.name: Translation.tr("Back to modules")
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "arrow_back"
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledToolTip { text: Translation.tr("Back to modules") }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.localized(root.selectedModule?.name, root.selectedId)
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            MaterialSymbol {
                                text: root.slotIcon(root.selectedModule)
                                iconSize: 34
                                color: Appearance.colors.colPrimary
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.localized(root.selectedModule?.name, root.selectedId)
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.title
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    font.variableAxes: Appearance.font.variableAxes.title
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: "v" + (root.selectedModule?.version ?? "") + " · "
                                        + root.slotLabel(root.selectedModule) + " · "
                                        + (root.selectedModule?.tierB === true ? Translation.tr("Patched") : Translation.tr("Safe"))
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            Item {
                                width: 52
                                height: 44
                                StyledSwitch {
                                    anchors.centerIn: parent
                                    scale: 0.85
                                    enabled: root.isFlippable(root.selectedModule)
                                        && !root.operationFor(root.selectedId).busy && !flipProc.running
                                    checked: root.selectedModule?.state === "enabled"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.isFlippable(root.selectedModule)
                                        && !root.operationFor(root.selectedId).busy && !flipProc.running
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.flip(root.selectedId, root.selectedModule.state !== "enabled")
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: Translation.tr("Enable %1").arg(root.localized(root.selectedModule?.name, root.selectedId))
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: root.operationFor(root.selectedId).busy
                                    text: "progress_activity"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnSurfaceVariant
                                    RotationAnimation on rotation {
                                        running: root.operationFor(root.selectedId).busy
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 900
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root.hasSelection && !root.isFlippable(root.selectedModule)
                            implicitHeight: unavailableRow.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colErrorContainer
                            RowLayout {
                                id: unavailableRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                spacing: 8
                                MaterialSymbol {
                                    text: "error"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnErrorContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: root.selectedModule?.state === "incompatible"
                                        ? Translation.tr("This module is incompatible with the current shell.")
                                        : Translation.tr("This module is blocked by a dependency.")
                                    color: Appearance.colors.colOnErrorContainer
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root.operationFor(root.selectedId).error.length > 0
                            implicitHeight: operationErrorRow.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colErrorContainer
                            RowLayout {
                                id: operationErrorRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                spacing: 8
                                MaterialSymbol {
                                    text: "error"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnErrorContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: root.operationFor(root.selectedId).error
                                    color: Appearance.colors.colOnErrorContainer
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root.selectedModule?.tierB === true
                            implicitHeight: patchWarningRow.implicitHeight + 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colSecondaryContainer
                            RowLayout {
                                id: patchWarningRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                spacing: 8
                                MaterialSymbol {
                                    text: "warning"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: Translation.tr("This module modifies stock shell files. iimod recomposes those changes when the module is enabled or disabled.")
                                    color: Appearance.colors.colOnSecondaryContainer
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            wrapMode: Text.WordWrap
                            text: root.localized(root.selectedModule?.description, "")
                            color: Appearance.colors.colOnSurfaceVariant
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: (root.selectedModule?.slots ?? []).indexOf("bar") !== -1
                            spacing: 6
                            StyledText {
                                text: Translation.tr("Bar placement")
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                MaterialSymbol {
                                    text: "swap_vert"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: Translation.tr("Vertical bar position")
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: true
                                currentValue: root.barPlacement(root.selectedId)
                                onSelected: newValue => root.setBarPlacement(root.selectedId, newValue)
                                options: [
                                    { displayName: Translation.tr("Top"), icon: "vertical_align_top", value: "top" },
                                    { displayName: Translation.tr("Above tray"), icon: "vertical_align_bottom", value: "bottom" },
                                ]
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                text: Translation.tr("Settings")
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                            Loader {
                                id: moduleSettingsLoader
                                Layout.fillWidth: true
                                active: root.hasSelection && !!root.selectedModule.settings
                                source: active
                                    ? Quickshell.shellPath(`mod/${root.selectedModule.id}/${root.selectedModule.settings}`)
                                    : ""
                                onStatusChanged: if (status === Loader.Error)
                                    console.warn(`[iimp] settings fragment failed: ${root.selectedId}`)
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: !root.selectedModule?.settings
                                spacing: 8
                                MaterialSymbol {
                                    text: "tune"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnLayer1Inactive
                                }
                                StyledText {
                                    text: Translation.tr("No configurable options")
                                    color: Appearance.colors.colOnLayer1Inactive
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Appearance.m3colors.m3outlineVariant
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Translation.tr("Module ID") + "  " + root.selectedId
                                color: Appearance.colors.colOnLayer1Inactive
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                            }
                            StyledText {
                                text: root.stateLabel(root.selectedModule)
                                color: root.isFlippable(root.selectedModule)
                                    ? Appearance.colors.colOnLayer1Inactive : Appearance.m3colors.m3error
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                    }
                }
            }
        }
    }
}
