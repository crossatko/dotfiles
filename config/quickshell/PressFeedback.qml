import QtQuick

// Press micro-interaction for a clickable item (Btn, Tile, ListRow, nav entries, bar chips): while `area` is pressed
// the item sinks (scales about its centre so its longest edge moves in by `depth` px, never below 0.96 / above 0.99),
// and on release it comes back with a small overshoot (Motion: pressMs down, emphasisMs up; reduced motion = none).
// Visual only (scale does not touch the layout); HoverGlow brightens under the pointer at the same time.
// Usage, inside the item:   PressFeedback { area: myMouseArea }
Item {
    id: pf
    property MouseArea area: null
    property Item target: parent
    property real depth: 2
    readonly property real pressedScale: !target ? 1
        : Math.max(0.96, Math.min(0.99, 1 - 2 * depth / Math.max(1, target.width, target.height)))
    readonly property bool down: area !== null && area.pressed && area.enabled

    visible: false
    onDownChanged: {
        downAnim.stop(); upAnim.stop()
        if (!target) return
        if (Motion.reduced) { target.scale = 1; return }
        if (down) { downAnim.to = pressedScale; downAnim.start() }
        else if (target.scale !== 1) upAnim.start()
    }
    NumberAnimation { id: downAnim; target: pf.target; property: "scale"; duration: Motion.pressMs; easing.type: Easing.OutCubic }
    NumberAnimation { id: upAnim; target: pf.target; property: "scale"; to: 1; duration: Motion.emphasisMs; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
}
