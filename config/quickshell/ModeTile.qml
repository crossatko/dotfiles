import QtQuick
import QtQuick.Layouts

// Big choice tile of a modal menu (Region / Window / Screen in the screenshot and recording menus): key badge
// top-left, large icon, title and a muted sub line. `sel` = highlighted (keyboard or hover). Hovering emits
// hovered() (the menu moves its selection there), a click emits clicked().
Rectangle {
    id: tile
    property string icon: ""
    property string title: ""
    property string sub: ""
    property string badge: ""
    property bool sel: false
    signal hovered()
    signal clicked()

    Layout.fillWidth: true
    Layout.preferredWidth: 1                 // equal shares in a RowLayout
    implicitHeight: 128
    radius: Theme.radiusModal
    color: sel ? Theme.alpha(Theme.accent, tileArea.pressed ? 0.36 : 0.26) : Theme.alpha(Theme.fg, 0.07)
    border.width: 1
    border.color: sel ? Theme.alpha(Theme.accent, 0.85) : Theme.alpha(Theme.overlay, 0.45)
    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    KeyBadge { x: 8; y: 8; text: tile.badge; sel: tile.sel }

    ColumnLayout {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
        anchors.verticalCenterOffset: 6
        spacing: 4
        Icon {
            text: tile.icon
            font.pixelSize: 32
            color: tile.sel ? Theme.accent : Theme.fgDim
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 6
        }
        Label { text: tile.title; font.pixelSize: 14; color: tile.sel ? Theme.fg : Theme.fgDim; Layout.alignment: Qt.AlignHCenter }
        Label {
            text: tile.sub; font.pixelSize: Theme.fontCaption; color: Theme.muted
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }
    }

    MouseArea {
        id: tileArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: tile.hovered()
        onClicked: tile.clicked()
    }
}
