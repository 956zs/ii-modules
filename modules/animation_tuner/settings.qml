import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.mod.animation_tuner
import "MotionMath.js" as MotionMath

ColumnLayout {
    id: root

    property var catalog: MotionMath.tokenCatalog()
    property var draftDocument: MotionMath.defaultDocument()
    property string selectedTokenId: "elementMove"
    property string searchText: ""
    property bool resetAllArmed: false
    property string presetName: ""
    property string loadedCommittedJson: ""
    property string loadError: ""
    readonly property var visibleTokens: root.filteredCatalog()
    readonly property var validation: MotionMath.validateDocument(root.draftDocument)
    readonly property bool dirty: JSON.stringify(root.draftDocument) !== root.loadedCommittedJson
    readonly property var selectedToken: root.catalog.find(token => token.id === root.selectedTokenId) ?? root.catalog[0]
    readonly property var selectedOverride: root.draftDocument.overrides[root.selectedTokenId] ?? null
    readonly property var previewDraft: root.selectedOverride && root.selectedOverride.enabled
        ? root.selectedOverride : root.selectedToken

    spacing: 10

    function clone(value) {
        return JSON.parse(JSON.stringify(value))
    }

    function loadSerialized(serialized) {
        const parsed = MotionMath.parseDocument(serialized)
        root.draftDocument = parsed.ok ? root.clone(parsed.document) : MotionMath.defaultDocument()
        root.loadedCommittedJson = parsed.ok && parsed.document.schemaVersion === JSON.parse(serialized).schemaVersion
            ? JSON.stringify(parsed.document) : serialized
        root.loadError = parsed.ok ? "" : parsed.errors.join("; ")
    }

    function filteredCatalog() {
        const needle = root.searchText.trim().toLowerCase()
        if (needle === "") return root.catalog
        return root.catalog.filter(token => token.id.toLowerCase().includes(needle)
            || token.label.toLowerCase().includes(needle))
    }

    function defaultOverride(id) {
        const token = root.catalog.find(candidate => candidate.id === id)
        return {
            enabled: true,
            easingKind: "bezier",
            durationMs: token.durationMs,
            delayMs: 0,
            velocity: token.velocity,
            bezierCurve: root.clone(token.bezierCurve)
        }
    }

    function updateOverride(patch) {
        const next = root.clone(root.draftDocument)
        const defaults = root.defaultOverride(root.selectedTokenId)
        const stored = next.overrides[root.selectedTokenId] ?? {}
        const current = Object.assign(defaults, stored)
        next.overrides[root.selectedTokenId] = Object.assign(current, patch)
        root.draftDocument = next
    }

    function updateSpring(patch) {
        const next = root.clone(root.draftDocument)
        next.springLab = Object.assign(next.springLab, patch)
        root.draftDocument = next
    }

    function applyDraft() {
        const result = MotionMath.validateDocument(root.draftDocument)
        if (!result.ok) return false
        const serialized = JSON.stringify(root.draftDocument)
        if (!cfg.commit(serialized)) return false
        root.loadedCommittedJson = serialized
        root.loadError = ""
        return true
    }

    function revertDraft() {
        cfg.revertDraft()
        root.loadSerialized(cfg.committedJson)
    }

    function resetSelectedToken() {
        const next = root.clone(root.draftDocument)
        delete next.overrides[root.selectedTokenId]
        root.draftDocument = next
    }

    function resetAll() {
        if (!root.resetAllArmed) {
            root.resetAllArmed = true
            resetArmTimer.restart()
            return
        }
        const next = root.clone(root.draftDocument)
        next.overrides = {}
        root.draftDocument = next
        root.resetAllArmed = false
    }

    function applyPreset(curve) {
        root.updateOverride({ enabled: true, easingKind: "bezier", bezierCurve: root.clone(curve) })
    }

    function saveCustomPreset() {
        const name = root.presetName.trim()
        if (name === "" || !root.selectedOverride || !root.selectedOverride.bezierCurve) return
        const next = root.clone(root.draftDocument)
        next.customPresets.push({ name, bezierCurve: root.clone(root.selectedOverride.bezierCurve) })
        root.draftDocument = next
        root.presetName = ""
    }

    function deleteCustomPreset(index) {
        const next = root.clone(root.draftDocument)
        next.customPresets.splice(index, 1)
        root.draftDocument = next
    }

    ConfigLoader {
        id: cfg
        writable: true
        onReadyChanged: if (ready) root.loadSerialized(committedJson)
        onCommittedJsonChanged: if (ready && !root.dirty) root.loadSerialized(committedJson)
    }

    Timer {
        id: resetArmTimer
        interval: 5000
        repeat: false
        onTriggered: root.resetAllArmed = false
    }

    StyledText {
        Layout.fillWidth: true
        text: Translation.tr("Animation Tuner")
        color: Appearance.colors.colOnSecondaryContainer
        font.pixelSize: Appearance.font.pixelSize.large
        font.weight: Font.DemiBold
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: Translation.tr("Edits the shell's eight central writable animation tokens. Duration, Bezier, and velocity apply to the shell; delay is available in the preview only.")
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    ConfigSwitch {
        text: Translation.tr("Reduced motion")
        buttonIcon: "motion_photos_off"
        checked: root.draftDocument.reducedMotion
        onCheckedChanged: {
            if (checked === root.draftDocument.reducedMotion) return
            const next = root.clone(root.draftDocument)
            next.reducedMotion = checked
            root.draftDocument = next
        }
    }
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        wrapMode: Text.WordWrap
        text: Translation.tr("Reduced motion sets duration to zero for controlled tokens while preserving saved values. Qt and Quickshell expose no system reduced-motion preference here, and this setting does not change inline spring animations or direct readonly curve references.")
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    MaterialTextField {
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search animation tokens")
        text: root.searchText
        onTextChanged: root.searchText = text
    }

    Flow {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: root.visibleTokens
            delegate: RippleButton {
                id: tokenButton

                required property var modelData
                required property int index
                buttonText: Translation.tr(modelData.label)
                toggled: root.selectedTokenId === modelData.id
                contentItem: StyledText {
                    text: tokenButton.buttonText
                    color: tokenButton.toggled
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer1
                }
                onClicked: root.selectedTokenId = modelData.id
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.visibleTokens.length === 0
        text: Translation.tr("No matching animation tokens")
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.visibleTokens.length > 0
        implicitHeight: editorColumn.implicitHeight + 12 * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: editorColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(root.selectedToken.label)
                    color: Appearance.colors.colOnLayer1
                    font.weight: Font.DemiBold
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 12

                    StyledText {
                        text: root.selectedToken.factory === "none"
                            ? Translation.tr("Direct values only")
                            : Translation.tr("Factory + direct values")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        text: Translation.tr("Preview-only delay")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            ConfigSwitch {
                text: Translation.tr("Override this token")
                buttonIcon: "tune"
                checked: root.selectedOverride && root.selectedOverride.enabled === true
                onCheckedChanged: {
                    if (checked === (root.selectedOverride && root.selectedOverride.enabled === true)) return
                    root.updateOverride({ enabled: checked })
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 620 ? 2 : 1
                columnSpacing: 12
                rowSpacing: 4
                enabled: root.selectedOverride && root.selectedOverride.enabled === true

                NumberField {
                    label: Translation.tr("Duration")
                    value: root.selectedOverride ? root.selectedOverride.durationMs : root.selectedToken.durationMs
                    from: 0
                    to: 10000
                    suffix: "ms"
                    onValueEdited: value => root.updateOverride({ durationMs: value })
                }
                NumberField {
                    label: Translation.tr("Preview delay")
                    value: root.selectedOverride ? root.selectedOverride.delayMs : 0
                    from: 0
                    to: 5000
                    suffix: "ms"
                    onValueEdited: value => root.updateOverride({ delayMs: value })
                }
                NumberField {
                    label: Translation.tr("Velocity")
                    value: root.selectedOverride ? root.selectedOverride.velocity : root.selectedToken.velocity
                    from: 0
                    to: 10000
                    decimals: 0
                    enabled: root.selectedToken.velocity > 0
                    onValueEdited: value => root.updateOverride({ velocity: value })
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.selectedToken.velocity > 0
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Velocity applies to shell consumers that read this token, but the fixed-distance preview does not represent it.")
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Verified stock presets")
                color: Appearance.colors.colOnSecondaryContainer
                font.weight: Font.DemiBold
            }
            ConfigSelectionArray {
                enabled: root.selectedOverride && root.selectedOverride.enabled === true
                currentValue: ""
                onSelected: value => root.applyPreset(JSON.parse(value))
                options: [
                    { displayName: Translation.tr("Expressive fast"), icon: "speed", value: JSON.stringify([0.42, 1.67, 0.21, 0.9, 1, 1]) },
                    { displayName: Translation.tr("Expressive default"), icon: "animation", value: JSON.stringify([0.38, 1.21, 0.22, 1, 1, 1]) },
                    { displayName: Translation.tr("Expressive slow"), icon: "slow_motion_video", value: JSON.stringify([0.39, 1.29, 0.35, 0.98, 1, 1]) },
                    { displayName: Translation.tr("Expressive effects"), icon: "auto_awesome", value: JSON.stringify([0.34, 0.8, 0.34, 1, 1, 1]) },
                    { displayName: Translation.tr("Emphasized"), icon: "gesture", value: JSON.stringify([0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]) },
                    { displayName: Translation.tr("Emphasized accelerate"), icon: "trending_up", value: JSON.stringify([0.3, 0, 0.8, 0.15, 1, 1]) },
                    { displayName: Translation.tr("Emphasized decelerate"), icon: "trending_down", value: JSON.stringify([0.05, 0.7, 0.1, 1, 1, 1]) },
                    { displayName: Translation.tr("Standard"), icon: "timeline", value: JSON.stringify([0.2, 0, 0, 1, 1, 1]) },
                    { displayName: Translation.tr("Standard accelerate"), icon: "east", value: JSON.stringify([0.3, 0, 1, 1, 1, 1]) },
                    { displayName: Translation.tr("Standard decelerate"), icon: "west", value: JSON.stringify([0, 0, 0, 1, 1, 1]) },
                ]
            }

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 520 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 4
                enabled: root.selectedOverride && root.selectedOverride.enabled === true

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Custom preset name")
                    text: root.presetName
                    onTextChanged: root.presetName = text
                    onAccepted: root.saveCustomPreset()
                }
                RippleButton {
                    buttonText: Translation.tr("Save preset")
                    enabled: root.presetName.trim().length > 0
                    onClicked: root.saveCustomPreset()
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: root.draftDocument.customPresets
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        spacing: 2

                        RippleButton {
                            buttonText: modelData.name
                            onClicked: root.applyPreset(modelData.bezierCurve)
                        }
                        RippleButton {
                            buttonText: Translation.tr("Delete")
                            onClicked: root.deleteCustomPreset(index)
                        }
                    }
                }
            }

            BezierEditor {
                Layout.fillWidth: true
                enabled: root.selectedOverride && root.selectedOverride.enabled === true
                curve: root.selectedOverride ? root.selectedOverride.bezierCurve : root.selectedToken.bezierCurve
                baselineCurve: root.selectedToken.bezierCurve
                onCurveEdited: curve => root.updateOverride({ bezierCurve: curve })
            }

            MotionPreview {
                Layout.fillWidth: true
                baselineMotion: root.selectedToken
                draft: root.previewDraft
                springLab: root.draftDocument.springLab
                reducedMotion: root.draftDocument.reducedMotion
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Spring Lab parameters")
                color: Appearance.colors.colOnSecondaryContainer
                font.weight: Font.DemiBold
            }
            ConfigSelectionArray {
                currentValue: ""
                onSelected: value => {
                    const preset = JSON.parse(value)
                    root.updateSpring({ spring: preset.spring, damping: preset.damping })
                }
                options: [
                    { displayName: Translation.tr("Stock panel"), icon: "web_asset", value: JSON.stringify({ spring: 2.5, damping: 0.3 }) },
                    { displayName: Translation.tr("Stock indicator"), icon: "radio_button_checked", value: JSON.stringify({ spring: 3, damping: 0.22 }) },
                    { displayName: Translation.tr("Stock hover"), icon: "ads_click", value: JSON.stringify({ spring: 5, damping: 0.3 }) },
                ]
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 620 ? 2 : 1
                columnSpacing: 12
                rowSpacing: 4

                NumberField {
                    label: Translation.tr("Mass")
                    value: root.draftDocument.springLab.mass
                    from: 0.01
                    to: 100
                    decimals: 2
                    stepSize: 0.1
                    onValueEdited: value => root.updateSpring({ mass: value })
                }
                NumberField {
                    label: Translation.tr("Spring strength")
                    value: root.draftDocument.springLab.spring
                    from: 0
                    to: 5
                    decimals: 2
                    stepSize: 0.1
                    onValueEdited: value => root.updateSpring({ spring: value })
                }
                NumberField {
                    label: Translation.tr("Damping")
                    value: root.draftDocument.springLab.damping
                    from: 0
                    to: 1
                    decimals: 2
                    stepSize: 0.05
                    onValueEdited: value => root.updateSpring({ damping: value })
                }
                NumberField {
                    label: Translation.tr("Epsilon")
                    value: root.draftDocument.springLab.epsilon
                    from: 0.0001
                    to: 1
                    decimals: 4
                    stepSize: 0.001
                    onValueEdited: value => root.updateSpring({ epsilon: value })
                }
                NumberField {
                    label: Translation.tr("Maximum velocity")
                    value: root.draftDocument.springLab.velocity
                    from: 0
                    to: 10000
                    onValueEdited: value => root.updateSpring({ velocity: value })
                }
                NumberField {
                    label: Translation.tr("Modulus")
                    value: root.draftDocument.springLab.modulus
                    from: 0
                    to: 100000
                    onValueEdited: value => root.updateSpring({ modulus: value })
                }
                NumberField {
                    label: Translation.tr("Preview delay")
                    value: root.draftDocument.springLab.delayMs
                    from: 0
                    to: 5000
                    suffix: "ms"
                    onValueEdited: value => root.updateSpring({ delayMs: value })
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.loadError.length > 0 || !root.validation.ok
                spacing: 2

                StyledText {
                    text: root.loadError.length > 0
                        ? Translation.tr("The saved configuration is invalid. Review the defaults below, then Apply to repair it:")
                        : Translation.tr("Fix these values before applying:")
                    color: Appearance.m3colors.m3error
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.loadError.length > 0
                    wrapMode: Text.WordWrap
                    text: root.loadError
                    color: Appearance.m3colors.m3error
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                Repeater {
                    model: root.validation.errors
                    delegate: StyledText {
                        required property string modelData
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "• " + modelData
                        color: Appearance.m3colors.m3error
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: root.dirty ? Translation.tr("Unapplied changes") : Translation.tr("No unapplied changes")
                    color: root.dirty ? Appearance.colors.colTertiary : Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    RippleButton {
                        buttonText: Translation.tr("Reset token")
                        enabled: root.selectedOverride !== null
                        onClicked: root.resetSelectedToken()
                    }
                    RippleButton {
                        buttonText: root.resetAllArmed
                            ? Translation.tr("Confirm reset all token overrides") : Translation.tr("Reset all token overrides")
                        onClicked: root.resetAll()
                    }
                    RippleButton {
                        buttonText: Translation.tr("Revert")
                        enabled: root.dirty
                        onClicked: root.revertDraft()
                    }
                    RippleButton {
                        id: applyButton

                        buttonText: Translation.tr("Apply")
                        enabled: root.dirty && root.validation.ok
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        contentItem: StyledText {
                            text: applyButton.buttonText
                            color: Appearance.colors.colOnPrimary
                        }
                        onClicked: root.applyDraft()
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        wrapMode: Text.WordWrap
        text: Translation.tr("Config file:") + " ~/.config/illogical-impulse/modules/animation_tuner.json"
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
