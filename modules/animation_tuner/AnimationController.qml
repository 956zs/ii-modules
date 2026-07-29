import QtQuick
import qs.modules.common
import qs.mod.animation_tuner
import "MotionMath.js" as MotionMath

Item {
    id: root

    required property ConfigLoader config
    property var originals: ({})
    property var currentDocument: MotionMath.defaultDocument()
    property bool captured: false
    property string lastError: ""

    visible: false

    function tokenIds() {
        return MotionMath.tokenCatalog().map(token => token.id)
    }

    function captureOriginals() {
        if (root.captured) return
        const snapshot = {}
        for (const id of root.tokenIds()) {
            const token = Appearance.animation[id]
            if (!token) continue
            snapshot[id] = {
                duration: token.duration,
                type: token.type,
                bezierCurve: Array.from(token.bezierCurve === undefined ? [] : token.bezierCurve),
                velocity: token.velocity === undefined ? 0 : token.velocity
            }
        }
        root.originals = snapshot
        root.captured = true
    }

    function restoreOriginals() {
        if (!root.captured) return
        for (const id in root.originals) {
            const token = Appearance.animation[id]
            const original = root.originals[id]
            if (!token || !original) continue
            token.duration = original.duration
            token.type = original.type
            if (token.bezierCurve !== undefined) token.bezierCurve = Array.from(original.bezierCurve)
            if (token.velocity !== undefined) token.velocity = original.velocity
        }
    }

    function applyDocument(serialized) {
        const parsed = MotionMath.parseDocument(serialized)
        root.captureOriginals()
        root.restoreOriginals()
        if (!parsed.ok) {
            root.currentDocument = MotionMath.defaultDocument()
            root.lastError = parsed.errors.join("; ")
            console.warn(`[animation_tuner] restored stock motion after invalid configuration: ${root.lastError}`)
            return false
        }

        root.currentDocument = parsed.document
        const tokenIds = parsed.document.reducedMotion ? root.tokenIds() : parsed.applicableTokens
        for (const id of tokenIds) {
            const token = Appearance.animation[id]
            const effective = MotionMath.effectiveToken(parsed.document, id)
            if (!token || !effective) continue
            token.duration = effective.durationMs
            token.type = Easing.BezierSpline
            token.bezierCurve = Array.from(effective.bezierCurve)
            if (token.velocity !== undefined) token.velocity = effective.velocity
        }
        root.lastError = ""
        return true
    }

    Connections {
        target: root.config
        function onDocumentJsonChanged() {
            if (root.config.ready) root.applyDocument(root.config.documentJson)
        }
        function onReadyChanged() {
            if (root.config.ready) root.applyDocument(root.config.documentJson)
        }
    }

    Component.onCompleted: {
        root.captureOriginals()
        if (root.config.ready) root.applyDocument(root.config.documentJson)
    }
    Component.onDestruction: root.restoreOriginals()
}
