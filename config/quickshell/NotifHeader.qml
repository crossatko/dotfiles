import QtQuick
import QtQuick.Layouts

// The notification center's bottom row (the file keeps its old name: it was the header, and a renamed type needs a
// shell restart): a scroll hint (only while the list overflows) and Clear. Plain on the desktop (no glass, fill, border or blur region).
Item {
    id: row
    property bool overflow: false      // more cards than fit: the list scrolls

    implicitHeight: line.implicitHeight      // just the tallest child (Clear)

    RowLayout {
        id: line
        anchors { left: parent.left; right: parent.right }   // flush with the cards' edges
        spacing: Theme.controlGap
        Label {
            Layout.fillWidth: true
            text: row.overflow ? "scroll for more" : ''
            color: Theme.fgDim
            font.pixelSize: Theme.fontSmall
        }
        Btn { text: "Clear"; enabledLook: Notifs.liveCount > 0; onClicked: Notifs.clearAll() }
    }
}
