import QtQuick

// Horizontal slider, 0..1. `value` is the real state; dragging emits moved(v) and never sets `value`
// itself, so it always shows the truth.
Item {
    id: sl
    property real value: 0
    property bool dim: false
    property real floor: 0              // lowest value a drag / wheel can emit (brightness keeps screens from going black)
    signal moved(real v)

    implicitHeight: 24
    opacity: dim ? 0.5 : 1

    readonly property real shown: drag.pressed ? drag.live : value

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6
        radius: Math.min(height / 2, Theme.radius)
        color: Theme.alpha(Theme.fg, 0.14)
        Rectangle {
            width: Math.max(0, Math.min(1, sl.shown)) * parent.width
            height: parent.height
            radius: parent.radius
            color: Theme.accent
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }
    }
    Rectangle {
        // Handle is always square (width == height). Radius = min(size / 2, Theme.radius): a square at
        // radius 0, rounder as the setting grows, a full circle once radius >= size / 2 (8 px).
        readonly property int size: 16
        width: size; height: size
        radius: Math.min(size / 2, Theme.radius)
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, sl.shown)) * (sl.width - width)
        color: Theme.fg
        scale: drag.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        property real live: 0
        function set(x) { live = Math.max(sl.floor, Math.min(1, x / width)); sl.moved(live) }
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x) }
        onWheel: w => { live = Math.max(sl.floor, Math.min(1, sl.value + (w.angleDelta.y > 0 ? 0.03 : -0.03))); sl.moved(live) }
    }
}
