import QtQuick
import QtQuick.Layouts

// One recessed module on the bar. Children go in the row; set `active` for the
// accent-filled look and connect `clicked`/`wheel` for interaction.
Rectangle {
    id: chip

    default property alias content: row.data
    property bool active: false
    property bool dim: false
    signal clicked(var mouse)
    signal wheel(int dy)

    implicitHeight: Theme.barHeight - 12
    implicitWidth: row.implicitWidth + 20
    radius: Theme.radiusChip   // inset barPad inside the bar
    color: active ? Theme.alpha(Theme.accent, 0.28)
         : hover.containsMouse ? Theme.alpha(Theme.fg, 0.10)
         : Theme.alpha(Theme.bg, 0.35)
    border.width: active ? 1 : 0
    border.color: Theme.alpha(Theme.accent, 0.8)
    opacity: dim ? 0.55 : 1

    Behavior on color { ColorAnimation { duration: 120 } }

    RowLayout {
        id: row
        anchors { verticalCenter: parent.verticalCenter; horizontalCenter: parent.horizontalCenter }
        height: parent.height
        spacing: 6
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        z: -1                  // under the content so children (tray icons) get their own clicks
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => chip.clicked(mouse)
        onWheel: w => chip.wheel(w.angleDelta.y)
    }
}
