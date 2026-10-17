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
    // the rule takes all the width the title, detail and trailing items leave
    Item {
        Layout.fillWidth: true
        Layout.minimumWidth: 8
        Layout.preferredHeight: 1
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: Theme.alpha(Theme.overlay, 0.55) }
    }
    Label { visible: head.detail !== ""; text: head.detail; color: Theme.muted; font.pixelSize: 11 }
    RowLayout { id: extra; spacing: 6; visible: visibleChildren.length > 0 }   // no slot (or gap) while the trailing item is hidden
}
