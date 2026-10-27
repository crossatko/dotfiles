import QtQuick

// The unfolding part of an inline dropdown (DropSelect, DevicePicker, BtProfilePicker): zero height while closed, grows
// to `contentHeight` while `open` (the panel around it resizes with it) and clips. The options fade in and settle down
// a few px as it opens, and fade out first as it closes (Motion.moveMs for the height, hoverMs for the fade; reduced
// motion = instant).
// Usage:   FoldBox { Layout.fillWidth: true; open: x.open; contentHeight: list.implicitHeight
//                    ColumnLayout { id: list; width: parent.width; ... } }
Item {
    id: fb
    property bool open: false
    property real contentHeight: 0
    default property alias content: inner.data

    implicitHeight: open ? contentHeight : 0
    clip: true
    visible: implicitHeight > 0
    Behavior on implicitHeight { NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }

    Item {
        id: inner
        width: parent.width
        height: fb.contentHeight
        opacity: fb.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
        transform: Translate {
            y: fb.open ? 0 : -6
            Behavior on y { NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
        }
    }
}
