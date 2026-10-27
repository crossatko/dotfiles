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
    spacing: Theme.padSm

    Item {
        Layout.preferredWidth: Theme.iconCol - Theme.gapTight
        Layout.preferredHeight: Theme.controlH
        Layout.alignment: Qt.AlignTop
        Icon { anchors.centerIn: parent; text: fr.icon; font.pixelSize: Theme.iconMd; color: fr.iconColor }
    }
    RowLayout {
        id: body
        Layout.fillWidth: true
        spacing: Theme.controlGap
    }
}
