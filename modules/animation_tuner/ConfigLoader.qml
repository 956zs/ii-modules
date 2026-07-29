import Quickshell.Io
import qs.modules.common

FileView {
    id: root

    property bool ready: false
    property bool writable: false
    property string documentJson: storedDocumentJson
    property string committedJson: storedDocumentJson
    property string draftJson: committedJson
    property alias storedDocumentJson: adapterItem.documentJson

    path: Directories.shellConfig + "/modules/animation_tuner.json"
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: {
        if (root.writable) writeAdapter()
    }
    onLoaded: {
        root.committedJson = root.storedDocumentJson
        root.draftJson = root.committedJson
        root.ready = true
    }
    onLoadFailed: error => {
        if (error == FileViewError.FileNotFound) {
            root.committedJson = root.storedDocumentJson
            root.draftJson = root.committedJson
            if (root.writable) writeAdapter()
            root.ready = true
        }
    }

    function commit(serialized) {
        if (!root.writable) return false
        root.storedDocumentJson = serialized
        root.committedJson = serialized
        root.draftJson = serialized
        return true
    }

    function revertDraft() {
        root.draftJson = root.committedJson
    }

    adapter: JsonAdapter {
        id: adapterItem
        property string documentJson: "{\"schemaVersion\":1,\"reducedMotion\":false,\"overrides\":{},\"springLab\":{\"mass\":1,\"spring\":2.5,\"damping\":0.3,\"epsilon\":0.01,\"velocity\":0,\"modulus\":0,\"delayMs\":0},\"customPresets\":[]}"
    }
}
