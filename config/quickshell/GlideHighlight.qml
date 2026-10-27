import QtQuick

// One selection marker for a group (launcher rows, Settings sidebar, Segmented): instead of every item switching its own
// "selected" fill on and off, this rectangle sits under the items and glides to the selected one (Motion.moveMs /
// easeMove; reduced motion = jumps). Style it like the selected fill it replaces (color, border, radius).
// Either give it `target` (an item anywhere; its rect is mapped into our parent, re-read when it moves or resizes)
// or set `want` yourself (in our parent's coordinates, e.g. computed from an index). It jumps instead of gliding the
// first time it is shown (no slide in from 0,0) and while `glide` is false.
// Place it BEFORE the items (or with a lower z) so it draws under them.
Rectangle {
    id: hl
    property Item target: null
    property bool glide: true
    // the target rect in our parent's coordinates; reads the target's (and its parent's) geometry so the binding
    // follows a positioner / layout moving it
    property rect want: {
        const t = hl.target
        if (!t || !hl.parent) return Qt.rect(0, 0, 0, 0)
        void [t.x, t.y, t.width, t.height, t.parent ? t.parent.x + t.parent.y + t.parent.width : 0, hl.parent.width]
        const p = t.mapToItem(hl.parent, 0, 0)
        return Qt.rect(p.x, p.y, t.width, t.height)
    }
    readonly property bool has: want.width > 0 && want.height > 0

    // gliding only once the first position has been drawn (a timer: layouts settle after the first binding pass)
    property bool settled: false
    Timer { id: settle; interval: 60; onTriggered: hl.settled = hl.visible && hl.has }
    onVisibleChanged: { settled = false; if (visible) settle.restart() }
    onHasChanged: { if (!has) settled = false; else if (!settled) settle.restart() }
    Component.onCompleted: settle.restart()
    readonly property bool animate: settled && glide && !Motion.reduced

    x: want.x; y: want.y; width: want.width; height: want.height
    visible: has
    Behavior on x { enabled: hl.animate; NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
    Behavior on y { enabled: hl.animate; NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
    Behavior on width { enabled: hl.animate; NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
    Behavior on height { enabled: hl.animate; NumberAnimation { duration: Motion.moveMs; easing.type: Motion.easeMove } }
}
