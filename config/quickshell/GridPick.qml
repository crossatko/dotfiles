pragma ComponentBehavior: Bound
import QtQuick

// A 3 x 3 position picker (Settings > Desktop clock): a small 16:9 screen with nine cells; the cell whose
// (x, y) in {0, 0.5, 1} equals (`px`, `py`) is lit, none when the saved position is between cells (Custom: the
// sliders under Customise…). picked(x, y) on click. Keyboard: Tab focuses it, arrows move the lit cell (picking).
Rectangle {
    id: gp
    property real px: 0
    property real py: 0
    property real tolerance: 0.01
    signal picked(real x, real y)

    implicitWidth: 112
    implicitHeight: 63
    radius: Theme.inner(Theme.radiusPage, 9)
    color: Theme.alpha(Theme.fg, 0.05)
    border.width: 1
    border.color: activeFocus ? Theme.alpha(Theme.fg, 0.6) : Theme.alpha(Theme.overlay, 0.5)
    activeFocusOnTab: true

    readonly property var steps: [0, 0.5, 1]
    function cell(v) { for (let i = 0; i < 3; i++) if (Math.abs(v - steps[i]) <= tolerance) return i; return -1 }
    readonly property int cx: cell(px)
    readonly property int cy: cell(py)
    function move(dx, dy) {
        const x = cx < 0 ? 1 : Math.max(0, Math.min(2, cx + dx))
        const y = cy < 0 ? 1 : Math.max(0, Math.min(2, cy + dy))
        gp.picked(steps[x], steps[y])
    }
    Keys.onLeftPressed: move(-1, 0)
    Keys.onRightPressed: move(1, 0)
    Keys.onUpPressed: move(0, -1)
    Keys.onDownPressed: move(0, 1)

    Grid {
        anchors { fill: parent; margins: 4 }
        columns: 3
        spacing: 3
        Repeater {
            model: 9
            Rectangle {
                id: c
                required property int index
                readonly property int ix: index % 3
                readonly property int iy: Math.floor(index / 3)
                readonly property bool on: ix === gp.cx && iy === gp.cy
                width: (gp.width - 8 - 6) / 3
                height: (gp.height - 8 - 6) / 3
                radius: Math.min(3, gp.radius)
                color: on ? Theme.alpha(Theme.accent, 0.7) : hov.containsMouse ? Theme.alpha(Theme.fg, 0.22) : Theme.alpha(Theme.fg, 0.10)
                Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gp.picked(gp.steps[c.ix], gp.steps[c.iy]) }
            }
        }
    }
}
