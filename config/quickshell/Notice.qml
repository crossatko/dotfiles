import QtQuick
import QtQuick.Layouts

// Boxed message inside a popup (confirmations, errors, setup steps, empty states): an item-radius card with a
// hairline border, children stacked in a column. `danger` = red tint (errors, "this cuts your connection"),
// else a neutral grey box. Buttons inside sit `padX` from its edge: Btn { outerRadius: Theme.radiusItem; inset: padX }.
Rectangle {
    id: box
    property bool danger: false
    property real padX: 12
    property real padY: 12
    property alias spacing: col.spacing
    default property alias content: col.data

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 2 * padY
    radius: Theme.radiusItem
    color: danger ? Theme.alpha(Theme.red, 0.16) : Theme.alpha(Theme.fg, 0.06)
    border.width: 1
    border.color: danger ? Theme.alpha(Theme.red, 0.7) : Theme.alpha(Theme.overlay, 0.6)

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: box.padX; rightMargin: box.padX }
        spacing: 6
    }
}
