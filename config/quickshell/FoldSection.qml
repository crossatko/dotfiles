import QtQuick
import QtQuick.Layouts

// Collapsible popup section (Tailscale, Mullvad in NetPanel): a SectionHead that always stays visible (title,
// `detail` summary, chevron, then the `trailing` items, usually the on/off Toggle) over the children, which fold
// away. A click anywhere on the head row folds / unfolds; the Toggle's own MouseArea sits above the head's, so the
// switch still works in one click without unfolding. The fold animates its height with the popup motion tokens
// (Theme.popupMoveMs and curves, same as the card resize it causes). While fully open the body takes part in the
// parent layout normally (fillHeight, so a ListView inside can be squeezed to its minimum).
ColumnLayout {
    id: fs
    property string title: ""
    property string detail: ""
    property bool open: false
    property alias trailing: tail.data
    property alias bodySpacing: body.spacing
    default property alias content: body.data

    spacing: 0      // the head <-> body gap is the body's topMargin, so it folds with it

    Item {
        Layout.fillWidth: true
        implicitHeight: head.implicitHeight
        MouseArea {
            id: headArea
            anchors { fill: parent; topMargin: -6; bottomMargin: -6 }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fs.open = !fs.open
        }
        SectionHead {
            id: head
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            title: fs.title
            detail: fs.detail
            Icon {
                text: "\uf078"
                font.pixelSize: 11
                color: headArea.containsMouse ? Theme.fg : Theme.fgDim
                rotation: fs.open ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.popupMoveMs; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            RowLayout { id: tail; spacing: Theme.controlGap }
        }
    }

    ColumnLayout {
        id: body
        // 0 = folded, 1 = open; may overshoot with the Back curve, so everything below clamps it
        property real reveal: fs.open ? 1 : 0
        readonly property real k: Math.max(0, Math.min(1, reveal))
        Behavior on reveal { NumberAnimation { duration: Theme.popupMoveMs; easing.type: fs.open ? Theme.popupEaseOpen : Theme.popupEaseClose } }

        visible: k > 0
        opacity: k
        clip: true
        spacing: 6
        Layout.fillWidth: true
        Layout.topMargin: 6 * k
        Layout.fillHeight: k >= 1
        Layout.minimumHeight: k >= 1 ? -1 : 0
        Layout.preferredHeight: k >= 1 ? -1 : implicitHeight * k
        Layout.maximumHeight: k >= 1 ? Number.POSITIVE_INFINITY : implicitHeight * k
    }
}
