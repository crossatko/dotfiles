import QtQuick
import QtQuick.Layouts

// Header of the notification center: title, count (with a scroll hint) and Clear, plain on the desktop (no glass,
// fill, border or blur region).
Item {
    id: head
    property bool overflow: false      // more cards than fit: the list scrolls

    implicitHeight: row.implicitHeight      // just the tallest child (Clear)

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right }   // flush with the cards' edges
        spacing: Theme.controlGap
        Label { text: "Notifications"; font.pixelSize: 15; font.bold: true; Layout.fillWidth: true }
        Label {
            visible: Notifs.liveCount > 0
            text: head.overflow ? Notifs.liveCount + "  ·  scroll for more" : Notifs.liveCount
            color: Theme.fgDim
            font.pixelSize: Theme.fontSmall
        }
        Btn { text: "Clear"; enabledLook: Notifs.liveCount > 0; onClicked: Notifs.clearAll() }
    }
}
