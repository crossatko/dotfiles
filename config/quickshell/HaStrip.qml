import QtQuick

// Colour strip (hue / saturation / colour temperature) for the Home Assistant popup. `colors` are the
// gradient stops left to right, `value` 0..1 is the real state; dragging emits moved(v) and never sets
// `value` itself (same contract as Slider).
Item {
    id: strip
    property var colors: ["#000000", "#ffffff"]
    property real value: -1                  // < 0: no marker (state unknown)
    signal moved(real v)

    implicitHeight: 16
    readonly property real shown: drag.pressed ? drag.live : value

    Row {
        anchors.fill: parent
        Repeater {
            model: Math.max(0, strip.colors.length - 1)
            Rectangle {
                required property int index
                width: strip.width / (strip.colors.length - 1)
                height: strip.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: strip.colors[index] }
                    GradientStop { position: 1; color: strip.colors[index + 1] }
                }
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.overlay, 0.7)
    }
    Rectangle {
        visible: strip.shown >= 0
        width: 6; height: strip.height + 6
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, strip.shown)) * (strip.width - width)
        color: "transparent"
        border.width: 2
        border.color: Theme.fg
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        property real live: 0
        function set(x) { live = Math.max(0, Math.min(1, x / width)); strip.moved(live) }
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x) }
    }
}
