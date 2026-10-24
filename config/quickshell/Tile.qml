import QtQuick
import QtQuick.Layouts

// Control-center quick toggle: icon + name + state line. Left click toggles, right click `secondary`.
Rectangle {
    id: tile
    property string icon: ""
    property string title: ""
    property string sub: ""
    property bool on: false
    signal clicked()
    signal secondary()

    implicitHeight: 54
    radius: Theme.radiusItem
    color: on ? Theme.alpha(Theme.accent, glow.hovered ? 0.30 : 0.26)
              : Theme.alpha(Theme.fg, glow.hovered ? 0.10 : 0.07)
    border.width: 1
    border.color: on ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.overlay, 0.45)
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    HoverGlow { id: glow; area: hoverArea; radius: tile.radius }
    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
        spacing: 10
        Icon { text: tile.icon; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 26; font.pixelSize: 20; color: tile.on ? Theme.accent : Theme.fgDim }
        RowText { title: tile.title; sub: tile.sub }
    }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? tile.secondary() : tile.clicked()
    }
}
