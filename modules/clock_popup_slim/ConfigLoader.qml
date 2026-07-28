import Quickshell.Io
import qs.modules.common

FileView {
    id: root

    property bool ready: false
    property bool owner: false
    property bool materializing: true

    path: Directories.shellConfig + "/modules/clock_popup_slim.json"
    watchChanges: true
    blockWrites: true
    atomicWrites: true

    onFileChanged: {
        root.materializing = true;
        reload();
    }
    onAdapterUpdated: {
        if (!root.materializing)
            writeAdapter();
    }
    onLoaded: {
        if (adapterItem.centerSideWidth < 280 || adapterItem.centerSideWidth > 360)
            adapterItem.centerSideWidth = 280;
        root.materializing = false;
        if (root.owner)
            writeAdapter();
        root.ready = true;
    }
    onLoadFailed: error => {
        if (error !== FileViewError.FileNotFound)
            return;
        root.materializing = false;
        if (root.owner)
            writeAdapter();
        root.ready = true;
    }

    property alias options: adapterItem
    adapter: JsonAdapter {
        id: adapterItem

        property bool showDate: false
        property string timeFormat: "HH:mm"
        property string dateFormat: "ddd, dd/MM"
        property string separator: "•"
        property int contentSpacing: 4
        property int horizontalPadding: 0
        property int centerSideWidth: 280
        property int timeSizeOffset: 0
        property int dateSizeOffset: 0
        property bool slimPopup: true
    }
}
