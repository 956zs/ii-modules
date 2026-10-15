import QtQuick
import QtQuick.Layouts

Item {
    default property alias items: gridLayout.children

    GridLayout {
        id: gridLayout
    }
}
