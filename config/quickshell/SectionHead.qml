import QtQuick
import QtQuick.Layouts

// Small group heading: label, a hairline rule, optional detail text and an optional trailing item
// (put a Toggle etc. in as a child).
RowLayout {
    id: head
    property string title: ""
    property string detail: ""
    default property alias trailing: extra.data

    Layout.fillWidth: true
    spacing: 8

    Label {
        text: head.title.toUpperCase()
        color: Theme.fgDim
        font.pixelSize: 11
        font.letterSpacing: 1.2
        font.bold: true
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.alpha(Theme.overlay, 0.55) }
    Label { visible: head.detail !== ""; text: head.detail; color: Theme.muted; font.pixelSize: 11 }
    RowLayout { id: extra; spacing: 6 }
}
