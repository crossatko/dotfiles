import QtQuick
import QtQuick.Layouts

// Boxed message inside a popup (confirmations, errors, setup steps, compact cards such as a VM or an AI profile): an
// item-radius card with a hairline border, children stacked in a column. `danger` = red tint (errors, "this cuts your
// connection"), else a neutral grey box. Buttons inside sit `padX` from its edge: Btn { outerRadius: Theme.radiusItem; inset: padX }.
Rectangle {
    id: box
    property bool danger: false
    property real padX: Theme.pad
    property real padY: Theme.pad
    property alias spacing: col.spacing
    default property alias content: col.data

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 2 * padY
    radius: Theme.radiusItem
    color: danger ? Theme.dangerFill : Theme.itemFill
    border.width: 1
    border.color: danger ? Theme.dangerEdge : Theme.alpha(Theme.overlay, 0.6)

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: box.padX; rightMargin: box.padX }
        spacing: Theme.controlGap
    }
}
