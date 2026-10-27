import QtQuick

// Dropdown / fold chevron: points down, turns to point up while `open` (Motion.moveMs, easeMove).
Icon {
    property bool open: false
    text: Icons.chevronDown
    font.pixelSize: 12
    color: Theme.fgDim
    rotation: open ? 180 : 0
    Behavior on rotation { NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
}
