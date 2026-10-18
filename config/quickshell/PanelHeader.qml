import QtQuick
import QtQuick.Layouts

// Title row at the top of a bar popup: bold title, optional status text, then whatever children the user adds
// (Btn, Toggle, ...) on the right. Without `showStatus` the title takes the free width; with it the status text
// does (it stays in the layout while empty, so the buttons never move).
RowLayout {
    id: head
    property string title: ""
    property bool showStatus: false
    property string status: ""
    property color statusColor: Theme.fgDim

    Layout.fillWidth: true
    spacing: 6

    Label { text: head.title; font.pixelSize: Theme.fontTitle; font.bold: true; Layout.fillWidth: !head.showStatus }
    Label {
        visible: head.showStatus
        Layout.fillWidth: true
        text: head.status
        color: head.statusColor
        font.pixelSize: Theme.fontSmall
        elide: Text.ElideRight
    }
}
