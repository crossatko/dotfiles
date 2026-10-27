pragma ComponentBehavior: Bound
import QtQuick

// Colour strip (hue / saturation / colour temperature) for the Home Assistant popup. `colors` are the
// gradient stops left to right, `value` 0..1 is the real state; dragging emits moved(v) and never sets
// `value` itself (same contract as Slider). `notches` as Slider's (NotchSnap: magnetic while dragging, double-click =
// the default notch), their ticks sit just under the strip (a tick on the colours would vanish on some of them).
Item {
    id: strip
    property var colors: ["#000000", "#ffffff"]
    property real value: -1                  // < 0: no marker (state unknown)
    property var notches: []
    signal moved(real v)

    readonly property int thumbW: 6          // width of the position marker
    implicitHeight: 16                       // strip thickness
    readonly property real shown: drag.pressed ? drag.live : value
    // rounded ends: only the first / last gradient segment gets the outer corners (per-corner radii, Qt >= 6.7)
    readonly property real r: Math.min(height / 2, Theme.radiusDeep)

    // the marker centre runs over [thumbW / 2, width - thumbW / 2]: a press puts the marker under the pointer
    NotchSnap {
        id: notch
        notches: strip.notches
        start: strip.thumbW / 2
        length: Math.max(1, strip.width - strip.thumbW)
    }
    NotchTicks { snap: notch; centerY: strip.height + strip.thumbW / 2 + 2; defaultH: 4; extraH: 3 }

    Row {
        anchors.fill: parent
        Repeater {
            model: Math.max(0, strip.colors.length - 1)
            Rectangle {
                id: seg
                required property int index
                width: strip.width / (strip.colors.length - 1)
                height: strip.height
                topLeftRadius: index === 0 ? strip.r : 0
                bottomLeftRadius: index === 0 ? strip.r : 0
                topRightRadius: index === strip.colors.length - 2 ? strip.r : 0
                bottomRightRadius: index === strip.colors.length - 2 ? strip.r : 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: strip.colors[seg.index] }
                    GradientStop { position: 1; color: strip.colors[seg.index + 1] }
                }
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: strip.r
        color: Theme.alpha(Theme.fg, 0)
        border.width: 1
        border.color: Theme.edge
    }
    Rectangle {
        visible: strip.shown >= 0
        width: strip.thumbW; height: strip.height + strip.thumbW
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, strip.shown)) * (strip.width - width)
        scale: 1 + notch.pulse * 0.3            // a notch "click"
        color: Theme.alpha(Theme.fg, 0)
        border.width: 2
        border.color: Theme.fg
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        property real live: 0
        function set(x) { live = notch.snap(x, Math.max(0, Math.min(1, (x - notch.start) / notch.length))); strip.moved(live) }
        onPressed: mouse => { notch.free(); set(mouse.x) }
        onPositionChanged: mouse => { if (pressed) set(mouse.x) }
        onReleased: notch.free()
        onCanceled: notch.free()
        onDoubleClicked: { notch.free(); if (notch.defaultValue >= 0) { live = notch.defaultValue; notch.click(); strip.moved(live) } }
    }
}
