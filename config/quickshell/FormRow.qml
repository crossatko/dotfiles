import QtQuick
import QtQuick.Layouts

// One row of a compact popup form: a fixed leading column with a Font Awesome `icon` and the row's controls, put in
// as children. Leading columns line up from row to row; the icon stays level with the first 30 px control line.
RowLayout {
    id: fr
    property string icon: ""
    property color iconColor: Theme.fgDim
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: 10

    Item {
        Layout.preferredWidth: 18
        Layout.preferredHeight: 30
        Layout.alignment: Qt.AlignTop
        Icon { anchors.centerIn: parent; text: fr.icon; font.pixelSize: 13; color: fr.iconColor }
    }
    RowLayout {
        id: body
        Layout.fillWidth: true
        spacing: 6
    }
}
