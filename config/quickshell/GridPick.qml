pragma ComponentBehavior: Bound
import QtQuick

// A position picker on a small 16:9 screen (Settings > Desktop clock: 3 x 3; the Voice / Diacritics pill: 3 x 2): one cell per
// (x, y) of `xSteps` x `ySteps` (default {0, 0.5, 1} each); the cell equal to (`px`, `py`) is lit, none when the saved position
// is between cells (Custom: the sliders under Customise…). picked(x, y) on click. Keyboard: Tab focuses it, arrows move the
// lit cell (picking).
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

    property var xSteps: [0, 0.5, 1]
    property var ySteps: [0, 0.5, 1]
    readonly property int cols: xSteps.length
    readonly property int rows: ySteps.length
    function cell(v, steps) { for (let i = 0; i < steps.length; i++) if (Math.abs(v - steps[i]) <= tolerance) return i; return -1 }
    readonly property int cx: cell(px, xSteps)
    readonly property int cy: cell(py, ySteps)
    function move(dx, dy) {
        const x = cx < 0 ? Math.floor(cols / 2) : Math.max(0, Math.min(cols - 1, cx + dx))
        const y = cy < 0 ? Math.floor(rows / 2) : Math.max(0, Math.min(rows - 1, cy + dy))
        gp.picked(xSteps[x], ySteps[y])
    }
    Keys.onLeftPressed: move(-1, 0)
    Keys.onRightPressed: move(1, 0)
    Keys.onUpPressed: move(0, -1)
    Keys.onDownPressed: move(0, 1)

    Grid {
        anchors { fill: parent; margins: 4 }
        columns: gp.cols
        spacing: 3
        Repeater {
            model: gp.cols * gp.rows
            Rectangle {
                id: c
                required property int index
                readonly property int ix: index % gp.cols
                readonly property int iy: Math.floor(index / gp.cols)
                readonly property bool on: ix === gp.cx && iy === gp.cy
                width: (gp.width - 8 - 3 * (gp.cols - 1)) / gp.cols
                height: (gp.height - 8 - 3 * (gp.rows - 1)) / gp.rows
                radius: Math.min(3, gp.radius)
                color: on ? Theme.alpha(Theme.accent, 0.7) : hov.containsMouse ? Theme.alpha(Theme.fg, 0.22) : Theme.alpha(Theme.fg, 0.10)
                Behavior on color { ColorAnimation { duration: Motion.hoverMs; easing.type: Motion.easeHover } }
                MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: gp.picked(gp.xSteps[c.ix], gp.ySteps[c.iy]) }
            }
        }
    }
}
