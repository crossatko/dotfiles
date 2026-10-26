import QtQuick
import QtQuick.Layouts

// Compact calendar chooser: colour dot + name. Click = next calendar, right click = previous.
// `calendars` is [{id, name, color}], `index` the selected one.
Rectangle {
    id: pick
    property var calendars: []
    property int index: -1
    readonly property var current: index >= 0 && index < calendars.length ? calendars[index] : null
    property real outerRadius: Theme.radius
    property real inset: 12
    implicitHeight: 30
    implicitWidth: row.implicitWidth + 20
    radius: Math.min(Theme.inner(outerRadius, inset), Math.floor(height / 3))
    color: glow.hovered ? Theme.alpha(Theme.fg, 0.14) : Theme.alpha(Theme.fg, 0.07)
    Behavior on color { ColorAnimation { duration: 100 } }

    function step(d) { if (calendars.length > 1) index = (index + d + calendars.length) % calendars.length }

    RowLayout {
        id: row
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        spacing: 7
        Rectangle { visible: pick.current !== null; implicitWidth: 8; implicitHeight: 8; radius: 4; color: pick.current ? pick.current.color : "transparent" }
        Label {
            Layout.fillWidth: true
            text: pick.current ? pick.current.name : "No calendar"
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSmall
        }
    }
    HoverGlow { id: glow; area: hoverArea; radius: pick.radius }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => pick.step(mouse.button === Qt.RightButton ? -1 : 1)
    }
}
